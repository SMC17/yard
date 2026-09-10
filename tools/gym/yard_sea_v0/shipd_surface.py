"""Ship-D surface: 49 constraints + STL + HP Calc_Volumes hydrostatics.

Wraps public upstream https://github.com/noahbagz/ShipD (vendored under
vendor/shipd_upstream/). Feasibility rule matches upstream README:

    constraints = Hull.input_Constraints()
    feasible iff sum(constraints > 0) == 0

Also exposes ``calc_volumes`` (Calc_VolumeProperties / Calc_Volumes) for
displacement, LCB, VCB, and waterplane metrics. Default grid ~30 ms; see
module cost notes. Not class / ITTC.
"""

from __future__ import annotations

import sys
import time
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Any, Sequence

import numpy as np

from .hull import HullState
from .shipd import LABELS, ShipDVector, project_to_hull

_VENDOR = Path(__file__).resolve().parents[1] / "vendor" / "shipd_upstream"

CONSTRAINT_GROUPS: tuple[tuple[str, int], ...] = (
    ("general", 2),
    ("cross_section", 7),
    ("bow", 15),
    ("stern", 12),
    ("bulb", 13),
)
N_CONSTRAINTS = sum(n for _, n in CONSTRAINT_GROUPS)
assert N_CONSTRAINTS == 49


def upstream_available() -> bool:
    return (_VENDOR / "HullParameterization.py").is_file()


def _ensure_vendor_on_path() -> None:
    root = str(_VENDOR)
    if root not in sys.path:
        sys.path.insert(0, root)


def _hull_param(vector: Sequence[float] | ShipDVector | np.ndarray):
    if not upstream_available():
        raise ImportError(
            f"Ship-D upstream missing at {_VENDOR}; expected HullParameterization.py"
        )
    _ensure_vendor_on_path()
    from HullParameterization import Hull_Parameterization as HP  # type: ignore

    if isinstance(vector, ShipDVector):
        arr = np.asarray(vector.values, dtype=np.float64)
    else:
        arr = np.asarray(list(vector), dtype=np.float64)
    if arr.shape != (45,):
        raise ValueError(f"Ship-D vector must be length 45, got shape {arr.shape}")
    return HP(arr)


@dataclass(frozen=True)
class ConstraintReport:
    """Report from Hull_Parameterization.input_Constraints (49 floats)."""

    values: tuple[float, ...]
    violated: tuple[bool, ...]
    n_violations: int
    feasible: bool
    group_violations: dict[str, int] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "n": len(self.values),
            "n_violations": self.n_violations,
            "feasible": self.feasible,
            "violated": list(self.violated),
            "values": list(self.values),
            "group_violations": dict(self.group_violations),
            "source": "Hull_Parameterization.input_Constraints",
            "rule": "feasible iff all values <= 0 (upstream: sum(c > 0) == 0)",
        }


def evaluate_constraints(
    vector: Sequence[float] | ShipDVector | np.ndarray,
) -> ConstraintReport:
    """Evaluate the 49 algebraic Ship-D constraints on a length-45 vector."""
    hull = _hull_param(vector)
    raw = np.asarray(hull.input_Constraints(), dtype=np.float64).reshape(-1)
    if raw.size != N_CONSTRAINTS:
        raise RuntimeError(
            f"expected {N_CONSTRAINTS} constraints from upstream, got {raw.size}"
        )
    violated = tuple(bool(v > 0.0) for v in raw)
    n_viol = sum(violated)
    group_viol: dict[str, int] = {}
    i = 0
    for name, n in CONSTRAINT_GROUPS:
        group_viol[name] = sum(violated[i : i + n])
        i += n
    return ConstraintReport(
        values=tuple(float(x) for x in raw),
        violated=violated,
        n_violations=int(n_viol),
        feasible=n_viol == 0,
        group_violations=group_viol,
    )


def generate_stl(
    vector: Sequence[float] | ShipDVector | np.ndarray,
    path: Path | str,
    *,
    num_wl: int = 40,
    points_per_wl: int = 120,
    add_transom: bool = True,
    add_deck_lid: bool = True,
    require_feasible: bool = True,
) -> Path:
    """Generate a Ship-D surface STL via upstream gen_stl.

    ``path`` may be with or without ``.stl``; upstream appends ``.stl`` to namepath.
    Returns the final ``.stl`` Path.
    """
    path = Path(path)
    if require_feasible:
        report = evaluate_constraints(vector)
        if not report.feasible:
            raise ValueError(
                f"Ship-D vector infeasible: {report.n_violations}/49 constraints violated"
            )
    path.parent.mkdir(parents=True, exist_ok=True)
    # Upstream saves namepath + '.stl'
    if path.suffix.lower() == ".stl":
        namepath = path.with_suffix("")
        out = path
    else:
        namepath = path
        out = Path(str(path) + ".stl")
    hull = _hull_param(vector)
    hull.gen_stl(
        NUM_WL=int(num_wl),
        PointsPerWL=int(points_per_wl),
        bit_AddTransom=1 if add_transom else 0,
        bit_AddDeckLid=1 if add_deck_lid else 0,
        namepath=str(namepath),
    )
    if not out.is_file():
        raise FileNotFoundError(f"upstream gen_stl did not write {out}")
    return out


def to_hull_state(
    vector: Sequence[float] | ShipDVector | np.ndarray,
    **kwargs: Any,
) -> HullState:
    """Project Ship-D vector to exploratory HullState (same as shipd.project_to_hull)."""
    return project_to_hull(vector, **kwargs)


def labels_from_upstream() -> list[str]:
    """Load X_LABELS.npy from vendor (string list of 45 names)."""
    arr = np.load(_VENDOR / "X_LABELS.npy", allow_pickle=True)
    names = [str(x) for x in arr.tolist()]
    if names != LABELS:
        # Prefer gym schema; warn via return of upstream for diagnostics
        pass
    return names




def michell_waterline_offsets(
    vector: Sequence[float] | ShipDVector | np.ndarray,
    *,
    nx: int = 41,
    nz: int = 11,
    draft: float | None = None,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Michell-ready (Y, X, Z) from Ship-D HP waterlines.

    Thin forwarder to ``teachers.michell_l15.shipd_waterline_offsets`` so surface
    callers can extract stations/waterlines without importing the teacher.
    """
    from .teachers.michell_l15 import shipd_waterline_offsets

    return shipd_waterline_offsets(vector, nx=nx, nz=nz, draft=draft)
# ---------------------------------------------------------------------------
# HP surface hydrostatics (Calc_VolumeProperties / Calc_Volumes)
# ---------------------------------------------------------------------------
#
# Cost (box, sample0, measured 2026-09-10 ET):
#   NUM_WL=41, PointsPerWL=120   ~ 0.03 s  (default here; on-demand / every-N)
#   NUM_WL=101, PointsPerWL=1000 ~ 0.5 s   (upstream defaults; too heavy per step)
#
# Prefer reset / every-N-steps / explicit calls — not every env step unless
# hp_hydro_every_n=1 and the ~30 ms latency is acceptable.

RHO_SW_HP = 1025.0
DEFAULT_NUM_WL = 41
DEFAULT_POINTS_PER_WL = 120


@dataclass(frozen=True)
class HydroStation:
    """Hydrostatics at one waterline height z (m above baseline)."""

    z: float
    volume_m3: float
    displacement_t: float
    lcb_m: float  # from bow (HP x); midship = LOA/2
    vcb_m: float  # from baseline
    lcb_frac: float  # (midship - lcb_m) / LOA; +fwd / -aft (HullState)
    awp_m2: float
    lcf_m: float
    ixx_m4: float
    iyy_m4: float
    wsa_m2: float
    lwl_m: float
    cb: float | None = None  # volume / (LOA * Bd_full * z) when z > 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "z_m": self.z,
            "volume_m3": self.volume_m3,
            "displacement_t": self.displacement_t,
            "lcb_m": self.lcb_m,
            "vcb_m": self.vcb_m,
            "lcb_frac": self.lcb_frac,
            "awp_m2": self.awp_m2,
            "lcf_m": self.lcf_m,
            "ixx_m4": self.ixx_m4,
            "iyy_m4": self.iyy_m4,
            "wsa_m2": self.wsa_m2,
            "lwl_m": self.lwl_m,
            "cb": self.cb,
        }


@dataclass(frozen=True)
class VolumesReport:
    """Output of Hull_Parameterization.Calc_VolumeProperties (+ Calc_Volumes)."""

    z: tuple[float, ...]
    volumes: tuple[float, ...]
    lcb: tuple[float, ...]
    vcb: tuple[float, ...]
    awp: tuple[float, ...]
    lcf: tuple[float, ...]
    ixx: tuple[float, ...]
    iyy: tuple[float, ...]
    wsa: tuple[float, ...]
    lwl: tuple[float, ...]
    loa: float
    bd_full: float
    dd: float
    design_draft: float
    stations: tuple[HydroStation, ...]
    num_wl: int
    points_per_wl: int
    elapsed_s: float
    cached: bool = False

    def primary(self) -> HydroStation:
        """First requested station (design draft when drafts omitted)."""
        if not self.stations:
            raise RuntimeError("VolumesReport has no stations")
        return self.stations[0]

    def to_dict(self) -> dict[str, Any]:
        return {
            "source": "Hull_Parameterization.Calc_VolumeProperties",
            "num_wl": self.num_wl,
            "points_per_wl": self.points_per_wl,
            "elapsed_s": self.elapsed_s,
            "cached": self.cached,
            "loa_m": self.loa,
            "bd_full_m": self.bd_full,
            "dd_m": self.dd,
            "design_draft_m": self.design_draft,
            "stations": [s.to_dict() for s in self.stations],
            "primary": self.primary().to_dict() if self.stations else None,
            "n_curve": len(self.z),
            "cost_note": (
                "default 41/120 ~30ms; upstream 101/1000 ~0.5s — "
                "use on-demand / every-N, not every step unless needed"
            ),
        }


def _vector_key(arr: np.ndarray) -> tuple[float, ...]:
    return tuple(
        float(np.format_float_positional(x, precision=12, unique=True)) for x in arr
    )


def _as_45(vector: Sequence[float] | ShipDVector | np.ndarray) -> np.ndarray:
    if isinstance(vector, ShipDVector):
        return np.asarray(vector.values, dtype=np.float64)
    arr = np.asarray(list(vector), dtype=np.float64)
    if arr.shape != (45,):
        raise ValueError(f"Ship-D vector must be length 45, got shape {arr.shape}")
    return arr


def _lerp_curve(A: np.ndarray, Z: np.ndarray, z: float) -> float:
    """Linear interpolate A(z) on ascending Z (mirrors upstream ``interp``)."""
    if z <= float(Z[0]):
        return float(A[0])
    if z >= float(Z[-1]):
        return float(A[-1])
    idx = int(np.where(Z < z)[0][-1])
    denom = float(Z[idx + 1] - Z[idx])
    if denom <= 0:
        return float(A[idx])
    frac = (z - float(Z[idx])) / denom
    return float(A[idx] + frac * (A[idx + 1] - A[idx]))


def _run_volume_curves(
    arr: np.ndarray, num_wl: int, points_per_wl: int
) -> tuple[tuple[float, ...], ...]:
    """Uncached Calc_VolumeProperties → curve tuples."""
    hull = _hull_param(arr)
    t0 = time.perf_counter()
    Z = np.asarray(
        hull.Calc_VolumeProperties(NUM_WL=int(num_wl), PointsPerWL=int(points_per_wl)),
        dtype=np.float64,
    )
    elapsed = time.perf_counter() - t0
    return (
        tuple(float(x) for x in Z),
        tuple(float(x) for x in hull.Volumes),
        tuple(float(x) for x in hull.VolumeCentroids[:, 0]),
        tuple(float(x) for x in hull.VolumeCentroids[:, 1]),
        tuple(float(x) for x in hull.Areas_WP),
        tuple(float(x) for x in hull.LCFs),
        tuple(float(x) for x in hull.I_WP[:, 0]),
        tuple(float(x) for x in hull.I_WP[:, 1]),
        tuple(float(x) for x in hull.Area_WS),
        tuple(float(x) for x in hull.WL_Lengths),
        float(hull.LOA),
        float(2.0 * hull.Bd),  # Bd is half-beam in HP
        float(hull.Dd),
        float(elapsed),
    )


@lru_cache(maxsize=64)
def _calc_volumes_curves(
    key: tuple[float, ...],
    num_wl: int,
    points_per_wl: int,
) -> tuple[tuple[float, ...], ...]:
    """Cached Calc_VolumeProperties keyed by rounded vector + grid."""
    return _run_volume_curves(np.asarray(key, dtype=np.float64), num_wl, points_per_wl)


def clear_volumes_cache() -> None:
    """Drop the optional LRU cache used by calc_volumes."""
    _calc_volumes_curves.cache_clear()


def calc_volumes(
    vector: Sequence[float] | ShipDVector | np.ndarray,
    drafts: float | Sequence[float] | None = None,
    *,
    num_wl: int = DEFAULT_NUM_WL,
    points_per_wl: int = DEFAULT_POINTS_PER_WL,
    use_cache: bool = True,
) -> VolumesReport:
    """Compute HP surface hydrostatics via Calc_VolumeProperties / Calc_Volumes.

    Parameters
    ----------
    vector
        Length-45 Ship-D input vector.
    drafts
        Waterline height(s) z in metres above baseline. ``None`` → design draft
        ``WL * Dd`` from the vector. May be a scalar or sequence.
    num_wl, points_per_wl
        Point-cloud resolution. Defaults are the cheap grid (~30 ms). Upstream
        demo uses 101 / 1000 (~0.5 s).
    use_cache
        LRU-cache curves by (rounded vector, num_wl, points_per_wl). Draft
        interpolation is free after the first call for the same hull/grid.

    Returns
    -------
    VolumesReport
        Full curves plus ``stations`` at each requested draft with displacement,
        LCB, VCB, waterplane (Awp, LCF, Ixx, Iyy), WSA, LWL, Cb.
    """
    arr = _as_45(vector)
    key = _vector_key(arr)
    if use_cache:
        before = _calc_volumes_curves.cache_info().hits
        curves = _calc_volumes_curves(key, int(num_wl), int(points_per_wl))
        cached = _calc_volumes_curves.cache_info().hits > before
    else:
        curves = _run_volume_curves(arr, int(num_wl), int(points_per_wl))
        cached = False

    (
        z_t,
        vol_t,
        lcb_t,
        vcb_t,
        awp_t,
        lcf_t,
        ixx_t,
        iyy_t,
        wsa_t,
        lwl_t,
        loa,
        bd_full,
        dd,
        elapsed_compute,
    ) = curves

    if isinstance(vector, ShipDVector):
        design_draft = float(vector.principal()["T"])
    else:
        design_draft = float(ShipDVector.from_sequence(arr).principal()["T"])

    if drafts is None:
        draft_list = [design_draft]
    elif isinstance(drafts, (float, int, np.floating, np.integer)):
        draft_list = [float(drafts)]
    else:
        draft_list = [float(d) for d in drafts]
    if not draft_list:
        raise ValueError("drafts must contain at least one value when provided")

    Z = np.asarray(z_t, dtype=np.float64)
    stations: list[HydroStation] = []
    for z in draft_list:
        vol = _lerp_curve(np.asarray(vol_t), Z, z)
        lcb = _lerp_curve(np.asarray(lcb_t), Z, z)
        vcb = _lerp_curve(np.asarray(vcb_t), Z, z)
        awp = _lerp_curve(np.asarray(awp_t), Z, z)
        lcf = _lerp_curve(np.asarray(lcf_t), Z, z)
        ixx = _lerp_curve(np.asarray(ixx_t), Z, z)
        iyy = _lerp_curve(np.asarray(iyy_t), Z, z)
        wsa = _lerp_curve(np.asarray(wsa_t), Z, z)
        lwl = _lerp_curve(np.asarray(lwl_t), Z, z)
        # HullState lcb_frac: +fwd (toward bow). HP x grows bow→stern.
        lcb_frac = ((0.5 * loa) - lcb) / loa if loa > 0 else 0.0
        denom = loa * bd_full * z if (loa > 0 and bd_full > 0 and z > 0) else None
        cb = (vol / denom) if denom else None
        stations.append(
            HydroStation(
                z=float(z),
                volume_m3=vol,
                displacement_t=vol * RHO_SW_HP / 1000.0,
                lcb_m=lcb,
                vcb_m=vcb,
                lcb_frac=float(lcb_frac),
                awp_m2=awp,
                lcf_m=lcf,
                ixx_m4=ixx,
                iyy_m4=iyy,
                wsa_m2=wsa,
                lwl_m=lwl,
                cb=float(cb) if cb is not None else None,
            )
        )

    return VolumesReport(
        z=z_t,
        volumes=vol_t,
        lcb=lcb_t,
        vcb=vcb_t,
        awp=awp_t,
        lcf=lcf_t,
        ixx=ixx_t,
        iyy=iyy_t,
        wsa=wsa_t,
        lwl=lwl_t,
        loa=loa,
        bd_full=bd_full,
        dd=dd,
        design_draft=design_draft,
        stations=tuple(stations),
        num_wl=int(num_wl),
        points_per_wl=int(points_per_wl),
        elapsed_s=0.0 if cached else float(elapsed_compute),
        cached=cached,
    )


def hull_from_volumes(
    vector: Sequence[float] | ShipDVector | np.ndarray,
    report: VolumesReport | None = None,
    *,
    fn: float = 0.20,
    kg_frac: float = 0.55,
    **calc_kwargs: Any,
) -> HullState:
    """Build HullState using HP volume metrics at design draft (beyond project_to_hull).

    Replaces projected Cb / lcb_frac with surface-integrated values; L/B/T still
    come from Ship-D principals.
    """
    base = project_to_hull(vector, fn=fn, kg_frac=kg_frac)
    if report is None:
        report = calc_volumes(vector, **calc_kwargs)
    st = report.primary()
    cb = st.cb if st.cb is not None and st.cb > 0 else base.Cb
    cb = float(max(0.35, min(0.98, cb)))
    lcb_frac = float(max(-0.08, min(0.08, st.lcb_frac)))
    return HullState(
        L=base.L,
        B=base.B,
        T=base.T,
        Cb=cb,
        lcb_frac=lcb_frac,
        kg_frac=kg_frac,
        Fn=fn,
    )
