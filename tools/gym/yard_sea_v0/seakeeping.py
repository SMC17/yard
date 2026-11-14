"""Seakeeping L2: Capytaine RAOs + zero-speed mean drift (added resistance proxy) in a sea state.

LABEL: ``seakeeping_l2_zero_speed_v0``. Scope, stated plainly:

* Geometry: a *wall-sided, flat-bottomed* hull whose half-breadth follows
  ``y(x) = B/2 · (1 - |2x/L|^p)`` with ``p = Cb / (1 - Cb)``, so the immersed
  volume honours ``L·B·T·Cb``. It is a ranking geometry derived from the
  ``HullState`` principals, not a Ship-D surface and not a real hull form.
* Hydrodynamics: Capytaine linear potential-flow BEM (radiation + diffraction),
  deep water, head seas, **zero forward speed**. Degrees of freedom: surge,
  heave, pitch. Mass = ρ·∇ (freely floating); pitch radius of gyration
  ``k_yy = 0.25·L`` is a *convention*, not a loading condition. No roll, no
  viscous damping, no bilge keels, no nonlinear (large-motion) effects.
* Added resistance: Capytaine's far-field (Maruo-type, Kochin-function) mean
  drift force in surge at zero speed, per unit wave amplitude squared. Forward
  speed raises added resistance in reality (encounter frequency, steady-flow
  interaction); that is **not modelled** here, so absolute numbers are
  low-biased. Use for *relative* ranking between candidate hulls only.
* Irregular sea: two-parameter (Bretschneider / ITTC-style) spectrum from
  ``Hs``, ``Tp``; mean added resistance = ``2 ∫ S(ω) · R_aw(ω)/ζa² dω`` on the
  solved ω grid, with the captured fraction of spectral energy reported. A
  coverage below ``min_coverage`` fails the acceptance check (no extrapolation).

Not ITTC 7.5-02-07-02.x, not ISO 15016, not STAWAVE, not class, not
model-test validated. Acceptance checks are physics sanity limits (long-wave
heave RAO → 1, pitch RAO/k → 1, drift → 0 in long waves, R_aw ≥ 0 in head seas),
not validation against measurements.
"""

from __future__ import annotations

import dataclasses
import math
import time
import warnings
from dataclasses import dataclass, field
from typing import Any, Sequence

import numpy as np

from .acceptance import accept_l1
from .hull import G, RHO_SW, HullState
from .resistance_l1 import estimate_resistance

LABEL = "seakeeping_l2_zero_speed_v0"
FIDELITY = "L2_seakeeping_zero_speed"
FIDELITY_PENDING = "L2_seakeeping_pending"
KYY_FRAC_CONVENTION = 0.25
NOT_A_COMPLIANCE_CLAIM = (
    "Capytaine zero-speed linear BEM on a Cb-matched wall-sided ranking hull. "
    "Not ITTC / ISO 15016 / STAWAVE, not class, not model-test validated; "
    "forward-speed effects on added resistance are not modelled."
)
DEFAULT_OMEGAS: tuple[float, ...] = tuple(np.round(np.linspace(0.25, 1.6, 16), 4))


def detect() -> dict[str, Any]:
    try:
        import capytaine as cpt
        from capytaine.post_pro import far_field_mean_drift_force, rao  # noqa: F401

        return {"available": True, "version": str(getattr(cpt, "__version__", "?"))}
    except Exception as exc:  # pragma: no cover - import failure path
        return {"available": False, "error": f"{type(exc).__name__}: {exc}"}


# ---------------------------------------------------------------- sea states
@dataclass(frozen=True)
class SeaState:
    """Long-crested head sea described by significant height and peak period."""

    Hs: float  # m
    Tp: float  # s
    name: str = "sea"
    heading: str = "head"  # only head seas are modelled

    def spectrum(self, omega: np.ndarray) -> np.ndarray:
        """Two-parameter Bretschneider / Pierson-Moskowitz-shape spectrum S(ω) [m²·s]."""
        w = np.asarray(omega, dtype=float)
        wp = 2.0 * math.pi / self.Tp
        with np.errstate(divide="ignore", over="ignore", invalid="ignore"):
            s = (5.0 / 16.0) * self.Hs**2 * wp**4 / w**5 * np.exp(-1.25 * (wp / w) ** 4)
        return np.where(w > 0, s, 0.0)

    def m0(self) -> float:
        return self.Hs**2 / 16.0

    def to_dict(self) -> dict[str, Any]:
        return {"name": self.name, "Hs": self.Hs, "Tp": self.Tp, "heading": self.heading,
                "spectrum": "bretschneider_two_parameter"}


# Example only: WMO sea-state code 4 spans Hs 1.25-2.5 m; Tp is a user choice.
EXAMPLE_SEA_STATE = SeaState(Hs=2.0, Tp=8.0, name="example_moderate_head_sea")


# ---------------------------------------------------------------- geometry
def waterplane_exponent(Cb: float) -> float:
    cb = min(max(float(Cb), 0.35), 0.98)
    return cb / (1.0 - cb)


def build_hull_mesh(h: HullState, *, nx: int = 40, ny: int = 6, nz: int = 4):
    """Immersed wall-sided ranking hull (outward normals), z ≤ 0, midship at x = 0."""
    import capytaine as cpt

    L, B, T = float(h.L), float(h.B), float(h.T)
    p = waterplane_exponent(h.Cb)
    xs = np.linspace(-L / 2.0, L / 2.0, nx + 1)
    zs = np.linspace(-T, 0.0, nz + 1)

    def half(x: float) -> float:
        return max(0.5 * B * (1.0 - abs(2.0 * x / L) ** p), 1e-3 * B)

    verts: list[np.ndarray] = []
    faces: list[list[int]] = []

    def quad(pts, out):
        a, b, c, d = (np.asarray(q, dtype=float) for q in pts)
        if np.dot(np.cross(c - a, d - b), out) < 0:
            b, d = d, b
        i = len(verts)
        verts.extend([a, b, c, d])
        faces.append([i, i + 1, i + 2, i + 3])

    for i in range(nx):
        x0, x1 = xs[i], xs[i + 1]
        y0, y1 = half(x0), half(x1)
        for k in range(nz):
            z0, z1 = zs[k], zs[k + 1]
            quad([(x0, y0, z0), (x1, y1, z0), (x1, y1, z1), (x0, y0, z1)], (0, 1, 0))
            quad([(x0, -y0, z0), (x1, -y1, z0), (x1, -y1, z1), (x0, -y0, z1)], (0, -1, 0))
        for j in range(ny):
            e0, e1 = -1.0 + 2.0 * j / ny, -1.0 + 2.0 * (j + 1) / ny
            quad([(x0, e0 * y0, -T), (x0, e1 * y0, -T), (x1, e1 * y1, -T), (x1, e0 * y1, -T)],
                 (0, 0, -1))
    return cpt.Mesh(vertices=np.array(verts), faces=np.array(faces), name="yard_sk_hull")


def _body(h: HullState, mesh_res: tuple[int, int, int], rho: float):
    import capytaine as cpt

    mesh = build_hull_mesh(h, nx=mesh_res[0], ny=mesh_res[1], nz=mesh_res[2])
    cog = (0.0, 0.0, float(h.kg()) - float(h.T))  # KG above keel → z relative to WL
    body = cpt.FloatingBody(mesh=mesh, dofs=cpt.rigid_body_dofs(rotation_center=cog),
                            center_of_mass=cog, name="yard_sk")
    body = body.immersed_part().with_only_dofs(["Surge", "Heave", "Pitch"])
    mass = rho * float(body.volume)
    inertia = body.compute_rigid_body_inertia(rho=rho)
    inertia[:] = np.diag([mass, mass, mass * (KYY_FRAC_CONVENTION * float(h.L)) ** 2])
    body.inertia_matrix = inertia
    body.hydrostatic_stiffness = body.compute_hydrostatic_stiffness(rho=rho)
    return body, mesh


# ---------------------------------------------------------------- solve
PANELS_PER_WAVELENGTH = 6.0  # convention for the mesh-resolution check


def shortest_wavelength(omega_max: float) -> float:
    return 2.0 * math.pi * G / float(omega_max) ** 2


def max_panel_size(h: HullState, mesh_res: Sequence[int]) -> float:
    return max(float(h.L) / mesh_res[0], float(h.B) / mesh_res[1], float(h.T) / mesh_res[2])


def auto_mesh_res(h: HullState, omega_max: float) -> tuple[int, int, int]:
    d = shortest_wavelength(omega_max) / PANELS_PER_WAVELENGTH
    return (max(24, math.ceil(float(h.L) / d)), max(4, math.ceil(float(h.B) / d)),
            max(3, math.ceil(float(h.T) / d)))


def solve(
    h: HullState | None = None,
    *,
    omegas: Sequence[float] = DEFAULT_OMEGAS,
    mesh_res: tuple[int, int, int] | None = None,
    rho: float = RHO_SW,
    n_theta: int = 181,
) -> dict[str, Any]:
    """Head-sea RAOs and zero-speed mean surge drift per ζa² on an ω grid.

    ``mesh_res=None`` picks (nx, ny, nz) so panels are ≤ λ_min / PANELS_PER_WAVELENGTH.
    """
    hull = h or HullState()
    if mesh_res is None:
        mesh_res = auto_mesh_res(hull, max(omegas))
    avail = detect()
    base = {"label": LABEL, "notes": NOT_A_COMPLIANCE_CLAIM, "hull": hull.to_dict(),
            "availability": avail, "omega": [float(w) for w in omegas]}
    if not avail["available"]:
        return {**base, "fidelity": FIDELITY_PENDING, "skipped": True,
                "skip_reason": "capytaine_missing_or_no_far_field_drift (needs capytaine>=3.0)"}

    import capytaine as cpt
    import xarray as xr
    from capytaine.post_pro import far_field_mean_drift_force, rao

    t0 = time.time()
    import logging

    logging.getLogger("capytaine").setLevel(logging.ERROR)
    try:
        body, mesh = _body(hull, mesh_res, rho)
        om = np.asarray(omegas, dtype=float)
        ds = xr.Dataset(coords={
            "omega": om, "wave_direction": [math.pi],  # waves travel toward -x: head seas
            "radiating_dof": list(body.dofs), "theta": np.linspace(0.0, 2 * math.pi, n_theta),
            "rho": [rho], "water_depth": [np.inf], "g": [G],
        })
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            data = cpt.BEMSolver().fill_dataset(ds, body, progress_bar=False)
            X = rao(data)
            drift = far_field_mean_drift_force(X, data)
    except Exception as exc:
        return {**base, "fidelity": FIDELITY_PENDING, "skipped": True,
                "skip_reason": f"capytaine_failed:{type(exc).__name__}: {exc}"}

    def _sq(a) -> np.ndarray:
        return np.asarray(a).reshape(len(om))

    heave = np.abs(_sq(X.sel(radiating_dof="Heave").values))
    pitch = np.abs(_sq(X.sel(radiating_dof="Pitch").values))
    k = om**2 / G
    fx = np.real(_sq(drift["drift_force_surge"].isel(wave_direction_k=0, wave_direction_l=0).values))
    raw = -fx  # head seas: drift pushes toward -x, i.e. resists ahead motion
    c33 = float(np.asarray(body.hydrostatic_stiffness.sel(influenced_dof="Heave", radiating_dof="Heave")))
    m = float(np.asarray(body.inertia_matrix.sel(influenced_dof="Heave", radiating_dof="Heave")))
    a33 = np.real(_sq(data["added_mass"].sel(influenced_dof="Heave", radiating_dof="Heave").values))
    return {
        **base,
        "fidelity": FIDELITY,
        "skipped": False,
        "capytaine_version": avail.get("version"),
        "mesh_res": list(mesh_res),
        "max_panel_m": max_panel_size(hull, mesh_res),
        "shortest_wavelength_m": shortest_wavelength(max(om)),
        "nb_faces": int(mesh.nb_faces),
        "immersed_volume_m3": float(body.volume),
        "target_volume_m3": float(hull.volume()),
        "kyy_frac_convention": KYY_FRAC_CONVENTION,
        "heave_rao": heave.tolist(),
        "pitch_rao_per_k": (pitch / k).tolist(),
        "drift_surge_per_zeta2": fx.tolist(),
        "raw_per_zeta2_N_m2": raw.tolist(),  # added resistance transfer function
        "reflection_limit_N_m2": 0.5 * rho * G * float(hull.B),
        "heave_natural_period_s_est": float(
            2 * math.pi * math.sqrt((m + float(np.median(a33))) / c33)) if c33 > 0 else None,
        "solve_s": time.time() - t0,
    }


def spectral_added_resistance(sol: dict[str, Any], sea: SeaState) -> dict[str, Any]:
    """Mean added resistance [N] in ``sea`` from the solved transfer function (trapezoid)."""
    om = np.asarray(sol["omega"], dtype=float)
    raw = np.asarray(sol["raw_per_zeta2_N_m2"], dtype=float)
    S = sea.spectrum(om)
    mean_raw = 2.0 * float(np.trapezoid(S * raw, om))
    coverage = float(np.trapezoid(S, om)) / sea.m0()
    return {"sea_state": sea.to_dict(), "mean_added_resistance_N": mean_raw,
            "spectral_coverage": coverage, "omega_range": [float(om[0]), float(om[-1])]}


@dataclass
class SeakeepingAcceptance:
    passed: bool
    checks: dict[str, bool] = field(default_factory=dict)
    values: dict[str, float] = field(default_factory=dict)

    @property
    def failed_checks(self) -> list[str]:
        return [k for k, v in self.checks.items() if not v]

    def to_dict(self) -> dict[str, Any]:
        return {"passed": self.passed, "checks": dict(self.checks),
                "failed_checks": self.failed_checks, "values": dict(self.values)}


def accept_seakeeping(
    sol: dict[str, Any], spectral: dict[str, Any] | None = None, *,
    longwave_tol: float = 0.1, min_coverage: float = 0.9, volume_tol: float = 0.03,
) -> SeakeepingAcceptance:
    """Physics sanity gate (not validation): limits a correct linear solve must respect."""
    if sol.get("skipped"):
        return SeakeepingAcceptance(False, {"solved": False})
    heave, pitch_k = sol["heave_rao"], sol["pitch_rao_per_k"]
    raw = np.asarray(sol["raw_per_zeta2_N_m2"])
    lim = float(sol["reflection_limit_N_m2"])
    vol_err = abs(sol["immersed_volume_m3"] / sol["target_volume_m3"] - 1.0)
    checks = {
        "solved": True,
        "volume_matches_Cb": vol_err <= volume_tol,
        "heave_rao_longwave_to_1": abs(heave[0] - 1.0) <= longwave_tol,
        "pitch_rao_longwave_to_k": abs(pitch_k[0] - 1.0) <= longwave_tol,
        "drift_longwave_to_0": bool(abs(raw[0]) <= 0.01 * lim),
        "raw_non_negative_head_seas": bool(np.all(raw >= -0.01 * lim)),
        "raw_finite": bool(np.all(np.isfinite(raw))),
        "mesh_resolves_shortest_wave": bool(
            sol["max_panel_m"] <= sol["shortest_wavelength_m"] / PANELS_PER_WAVELENGTH + 1e-9),
    }
    values = {"volume_rel_err": vol_err, "heave_rao_w0": heave[0], "pitch_rao_per_k_w0": pitch_k[0]}
    if spectral is not None:
        checks["spectral_coverage"] = spectral["spectral_coverage"] >= min_coverage
        values["spectral_coverage"] = spectral["spectral_coverage"]
    return SeakeepingAcceptance(all(checks.values()), checks, values)


# ---------------------------------------------------------------- multi-condition score
@dataclass(frozen=True)
class Condition:
    """Operating condition: calm water (``sea=None``) or a head sea at the same Fn."""

    name: str
    weight: float = 1.0
    sea: SeaState | None = None


DEFAULT_CONDITIONS: tuple[Condition, ...] = (
    Condition("calm", 1.0, None),
    Condition(EXAMPLE_SEA_STATE.name, 1.0, EXAMPLE_SEA_STATE),
)


def evaluate_conditions(
    h: HullState, conditions: Sequence[Condition] = DEFAULT_CONDITIONS, *,
    solve_kwargs: dict[str, Any] | None = None, _sol: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Total resistance [N] per condition: L1 calm Rt (+ zero-speed mean R_aw in a sea)."""
    r = estimate_resistance(h)
    acc_l1 = accept_l1(r)
    need_sea = any(c.sea is not None for c in conditions)
    sol = _sol if _sol is not None else (solve(h, **(solve_kwargs or {})) if need_sea else None)
    rows = []
    for c in conditions:
        row: dict[str, Any] = {"name": c.name, "weight": c.weight, "calm_Rt_N": float(r.Rt_N)}
        failed = list(acc_l1.failed_checks)
        if c.sea is None:
            row["total_N"] = float(r.Rt_N)
        else:
            spec = spectral_added_resistance(sol, c.sea) if sol and not sol.get("skipped") else None
            acc = accept_seakeeping(sol, spec) if sol else SeakeepingAcceptance(False, {"solved": False})
            failed += [f"seakeeping:{k}" for k in acc.failed_checks]
            row["seakeeping_acceptance"] = acc.to_dict()
            if spec is not None:
                row.update(spec)
                row["total_N"] = float(r.Rt_N) + spec["mean_added_resistance_N"]
                row["added_fraction"] = spec["mean_added_resistance_N"] / row["total_N"]
            else:
                row["total_N"] = None
        row["failed_checks"] = failed
        row["accepted"] = not failed and row["total_N"] is not None
        rows.append(row)
    return {"label": LABEL, "l1_fidelity": str(r.fidelity), "conditions": rows,
            "seakeeping": sol, "notes": NOT_A_COMPLIANCE_CLAIM}


def multi_condition_score(
    child: HullState, parent: HullState,
    conditions: Sequence[Condition] = DEFAULT_CONDITIONS, *,
    worst_case_weight: float = 1.0, solve_kwargs: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Relative total-resistance improvement of ``child`` over ``parent`` across conditions.

    ``score = weighted_mean(d) + worst_case_weight · min(0, min(d))`` with
    ``d = (parent - child) / parent`` per condition. A condition is credited only
    when both hulls pass L1 and seakeeping acceptance; if none are, ``score`` is None.
    """
    c_eval = evaluate_conditions(child, conditions, solve_kwargs=solve_kwargs)
    p_eval = evaluate_conditions(parent, conditions, solve_kwargs=solve_kwargs)
    rows = []
    for c, cr, pr in zip(conditions, c_eval["conditions"], p_eval["conditions"]):
        ok = cr["accepted"] and pr["accepted"] and (pr["total_N"] or 0) > 0
        d = (pr["total_N"] - cr["total_N"]) / pr["total_N"] if ok else None
        rows.append({"name": c.name, "weight": c.weight, "credited": ok, "d_total": d,
                     "child": cr, "parent": pr})
    cred = [r for r in rows if r["credited"]]
    out: dict[str, Any] = {"label": LABEL, "points": rows, "n_credited": len(cred),
                           "accepted": len(cred) == len(rows), "notes": NOT_A_COMPLIANCE_CLAIM,
                           "child_seakeeping": _summary(c_eval["seakeeping"]),
                           "parent_seakeeping": _summary(p_eval["seakeeping"])}
    if not cred:
        return {**out, "score": None, "reason": "no_condition_passed_acceptance"}
    wsum = sum(r["weight"] for r in cred) or 1.0
    mean_d = sum(r["weight"] * r["d_total"] for r in cred) / wsum
    worst = min(cred, key=lambda r: r["d_total"])
    return {**out, "score": mean_d + worst_case_weight * min(0.0, worst["d_total"]),
            "mean_d_total": mean_d, "worst_d_total": worst["d_total"], "worst_condition": worst["name"]}


def _summary(sol: dict[str, Any] | None) -> dict[str, Any] | None:
    if sol is None:
        return None
    keep = ("label", "fidelity", "skipped", "skip_reason", "capytaine_version", "nb_faces",
            "heave_natural_period_s_est", "solve_s")
    return {k: sol.get(k) for k in keep}


def with_principals(h: HullState, **kw: float) -> HullState:
    return dataclasses.replace(h, **kw)
