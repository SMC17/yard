"""Oracle validation against measured towing-tank data (not model-vs-model).

Every resistance oracle the gym uses is evaluated at *model scale* on public
benchmark hulls (KCS, JBC, KVLCC2, DTMB 5415) and compared with the measured
total resistance coefficient C_T. Reference values and their provenance live in
``data/reference/tank_resistance_reference.json`` (repo root); raw source files
are fetched by ``data/fetch/fetch_yard_data.py`` and are not redistributed.

Comparison convention (stated, not hidden):

* Error is the ITTC/Tokyo-2015 comparison error ``E%D = (D - S) / D * 100``
  (positive = oracle under-predicts). We also report ``|E|``.
* Every oracle is assembled into a model-scale C_T the same way:
  ``C_T,pred = C_F,ITTC57(Re_tank) * (1 + k_oracle) + R_W,oracle / (q * S0)``
  with ``q = 0.5 rho U^2`` and ``S0`` the source's wetted surface. Using the
  tank Reynolds number and the true ``S0`` removes water-property and
  wetted-surface bookkeeping so the comparison isolates the oracle's form
  factor and wave model, which is what drives the reward. No correlation
  allowance C_A is added (model scale).
* Oracles:
  - ``hm1984_full``  — Zig HM1984 with the hull's *published* C_M, C_P, S0,
    LCB; C_WP estimated (Schneekluth (1+2C_B)/3, not tabulated by sources);
    bulb / transom terms omitted (geometry not tabulated). Method error.
  - ``hm1984_gym``   — Zig HM1984 fed only what ``HullState`` carries
    (L, B, T, C_B, LCB; C_M=0.98, approximate S). What the reward actually sees.
  - ``simplified_py`` — Python Holtrop-simplified fallback.
  - ``michell_l15``  — L1 viscous (HM1984 gym form factor) + Michell thin-ship
    wave on the gym's synthetic Wigley-like offsets, wave drag normalised by
    wetted surface so it is on the same basis as the friction terms.
    ``michell_l15_L2basis`` reproduces the legacy composition ``multi_froude``
    used before yard#27's finding was fixed (Michell C_W on Ship-D's L^2 basis
    added to S-based friction terms) so the size of that inconsistency stays on
    the record. ``multi_froude`` now uses the S basis (``Cw_S``).

These are validation statistics for *this harness on these hulls*. They are not
ITTC verification & validation of the oracles and they are not class approval.
"""

from __future__ import annotations

import dataclasses
import json
import math
import subprocess
from pathlib import Path
from typing import Any, Callable, Iterable, Sequence

import numpy as np

from .hull import HullState
from .resistance_l1 import estimate_resistance, ittc57_cf

VALIDATION_SCHEMA = "yard_sea_v0.validation.tank.v1"

ORACLES = ("hm1984_full", "hm1984_gym", "simplified_py", "michell_l15", "michell_l15_L2basis")

# Envelope tolerance: an oracle is "validated" at a reference point when
# |E%D| <= this. 10 % is the usual ballpark quoted for Holtrop-type regressions
# inside their parent population; it is a stated convention, configurable.
DEFAULT_ENVELOPE_TOL_PCT = 10.0


def repo_root() -> Path:
    here = Path(__file__).resolve()
    for p in here.parents:
        if (p / "data" / "reference").is_dir():
            return p
    raise FileNotFoundError("repo-root data/reference not found above yard_sea_v0")


def reference_path() -> Path:
    return repo_root() / "data" / "reference" / "tank_resistance_reference.json"


def load_reference(path: str | Path | None = None) -> dict[str, Any]:
    return json.loads(Path(path or reference_path()).read_text())


@dataclasses.dataclass(frozen=True)
class TankCase:
    hull: str
    Fn: float
    CT: float
    L: float
    B: float
    T: float
    vol: float
    S0: float
    Cb: float
    Cm: float
    lcb_pct: float
    nu: float
    rho: float
    g: float
    dataset_id: str
    U_D_pct: float | None = None

    @property
    def U(self) -> float:
        return self.Fn * math.sqrt(self.g * self.L)

    @property
    def Re(self) -> float:
        return self.U * self.L / self.nu

    @property
    def Cp(self) -> float:
        return self.Cb / self.Cm

    @property
    def Cwp_est(self) -> float:
        return (1.0 + 2.0 * self.Cb) / 3.0

    def hull_state(self) -> HullState:
        return HullState(L=self.L, B=self.B, T=self.T, Cb=self.Cb, lcb_frac=self.lcb_pct / 100.0, Fn=self.Fn)

    def params(self) -> dict[str, float]:
        return {
            "Fn": self.Fn,
            "Cb": self.Cb,
            "Cp": self.Cp,
            "L_B": self.L / self.B,
            "B_T": self.B / self.T,
            "lcb_frac": self.lcb_pct / 100.0,
        }


def tank_cases(ref: dict[str, Any] | None = None) -> list[TankCase]:
    ref = ref or load_reference()
    out: list[TankCase] = []
    for name, h in ref["hulls"].items():
        m, fs = h["model"], h["full_scale"]
        g = float(m.get("g", 9.81))
        for p in h["points"]:
            L = float(m["Lpp"])
            nu = m.get("nu")
            if nu is None:  # source gives Re at the (single) test speed
                U = float(p["Fn"]) * math.sqrt(g * L)
                nu = U * L / float(m["Re"])
            out.append(
                TankCase(
                    hull=name, Fn=float(p["Fn"]), CT=float(p["CT"]), L=L, B=float(m["B"]), T=float(m["T"]),
                    vol=float(m["vol"]), S0=float(m["S0"]), Cb=float(fs["Cb"]), Cm=float(fs["Cm"]),
                    lcb_pct=float(fs["lcb_pct"]), nu=float(nu), rho=float(m.get("rho", 1000.0)), g=g,
                    dataset_id=str(h.get("dataset_id", name)),
                    U_D_pct=float(p.get("U_D_pct", h.get("data_uncertainty_pct", float("nan")))),
                )
            )
    return out


# ----------------------------------------------------------------- predictors
def _zig_bin() -> Path | None:
    try:
        from .zig_bridge import resolve_zig_binary

        return resolve_zig_binary()
    except FileNotFoundError:
        return None


def hm1984_full(c: TankCase, *, binary: Path | None = None) -> dict[str, Any]:
    b = binary or _zig_bin()
    if b is None:
        return {"available": False, "reason": "zig_gym binary not built"}
    args = [c.L, c.B, c.T, c.vol, c.S0, c.Cb, c.Cm, c.Cp, c.Cwp_est, c.lcb_pct, 0.0, c.Fn, c.nu, c.rho]
    proc = subprocess.run([str(b), "hm1984_full", *[repr(float(a)) for a in args]],
                          capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        return {"available": False, "reason": f"zig exit {proc.returncode}: {proc.stderr.strip()[:200]}"}
    l1 = json.loads(proc.stdout.strip().splitlines()[-1])["l1"]
    if "error" in l1:
        return {"available": False, "reason": l1["error"]}
    return {"available": True, "CT": float(l1["Ct_no_ca"]), "one_plus_k": float(l1["one_plus_k"]),
            "Cw_S0": float(l1["Cw"]), "Cf": float(l1["Cf"])}


def _assemble(c: TankCase, k: float, rw_over_q: float) -> float:
    return ittc57_cf(c.Re) * (1.0 + k) + rw_over_q / c.S0


def _gym_l1(c: TankCase, *, prefer_zig: bool) -> tuple[dict[str, Any], Any]:
    h = c.hull_state()
    r = estimate_resistance(h, prefer_zig_hm1984=prefer_zig)
    if prefer_zig and r.fidelity != "hm1984_zig":
        return {"available": False, "reason": "zig HM1984 unavailable"}, r
    s_gym = h.wetted_approx()
    rw_over_q = float(r.Cw) * s_gym
    return {"available": True, "CT": _assemble(c, float(r.k1), rw_over_q), "one_plus_k": 1.0 + float(r.k1),
            "Cw_S0": rw_over_q / c.S0, "S_gym_over_S0": s_gym / c.S0, "fidelity": r.fidelity}, r


def hm1984_gym(c: TankCase) -> dict[str, Any]:
    return _gym_l1(c, prefer_zig=True)[0]


def simplified_py(c: TankCase) -> dict[str, Any]:
    return _gym_l1(c, prefer_zig=False)[0]


def _michell_rw_over_q(c: TankCase) -> tuple[float | None, float | None, str | None]:
    from .teachers import michell_l15

    r = michell_l15.run(c.hull_state())
    if r.get("skipped") or r.get("Rw_N") is None:
        return None, None, str(r.get("skip_reason") or "michell_failed")
    U = float(r["U"])
    q = 0.5 * 1025.0 * U * U  # michell_l15 uses RHO_SW; ratio Rw/q is density-free
    return float(r["Rw_N"]) / q, float(r["Cw"]), None


def michell_l15(c: TankCase) -> dict[str, Any]:
    gym, r = _gym_l1(c, prefer_zig=True)
    if not gym.get("available"):
        gym, r = _gym_l1(c, prefer_zig=False)
    rwq, _cw_l2, why = _michell_rw_over_q(c)
    if rwq is None:
        return {"available": False, "reason": why}
    return {"available": True, "CT": _assemble(c, float(r.k1), rwq), "one_plus_k": 1.0 + float(r.k1),
            "Cw_S0": rwq / c.S0, "viscous_from": r.fidelity}


def michell_l15_L2basis(c: TankCase) -> dict[str, Any]:
    """Legacy composition: Michell C_W (Rw / (q L^2)) added as if it were S-based."""
    gym, r = _gym_l1(c, prefer_zig=True)
    if not gym.get("available"):
        gym, r = _gym_l1(c, prefer_zig=False)
    rwq, cw_l2, why = _michell_rw_over_q(c)
    if rwq is None:
        return {"available": False, "reason": why}
    return {"available": True, "CT": ittc57_cf(c.Re) * (1.0 + float(r.k1)) + float(cw_l2),
            "Cw_as_composed": float(cw_l2), "Cw_S0_physical": rwq / c.S0,
            "basis_ratio_S0_over_L2": c.S0 / c.L**2}


PREDICTORS: dict[str, Callable[[TankCase], dict[str, Any]]] = {
    "hm1984_full": hm1984_full,
    "hm1984_gym": hm1984_gym,
    "simplified_py": simplified_py,
    "michell_l15": michell_l15,
    "michell_l15_L2basis": michell_l15_L2basis,
}


# ------------------------------------------------------------------ statistics
def comparison_error_pct(measured: float, predicted: float) -> float:
    return (measured - predicted) / measured * 100.0


def _stats(errs: Sequence[float]) -> dict[str, Any]:
    e = np.asarray([x for x in errs if math.isfinite(x)], float)
    if e.size == 0:
        return {"n": 0}
    return {
        "n": int(e.size),
        "mean_E_pct": float(e.mean()),
        "mean_abs_E_pct": float(np.abs(e).mean()),
        "rms_E_pct": float(np.sqrt((e**2).mean())),
        "max_abs_E_pct": float(np.abs(e).max()),
    }


FN_BINS = ((0.0, 0.15), (0.15, 0.22), (0.22, 0.30), (0.30, 0.50))


def validate(
    oracles: Iterable[str] = ORACLES,
    *,
    cases: Sequence[TankCase] | None = None,
    envelope_tol_pct: float = DEFAULT_ENVELOPE_TOL_PCT,
) -> dict[str, Any]:
    cases = list(cases or tank_cases())
    names = [o for o in oracles]
    rows: list[dict[str, Any]] = []
    for c in cases:
        row: dict[str, Any] = {
            "hull": c.hull, "Fn": c.Fn, "Re": c.Re, "CT_measured": c.CT, "U_D_pct": c.U_D_pct,
            "dataset_id": c.dataset_id, "params": c.params(), "oracles": {},
        }
        for o in names:
            p = PREDICTORS[o](c)
            if p.get("available"):
                p["E_pct"] = comparison_error_pct(c.CT, p["CT"])
            row["oracles"][o] = p
        rows.append(row)

    per_oracle: dict[str, Any] = {}
    for o in names:
        errs = [r["oracles"][o].get("E_pct", float("nan")) for r in rows]
        by_hull = {
            h: _stats([r["oracles"][o].get("E_pct", float("nan")) for r in rows if r["hull"] == h])
            for h in sorted({r["hull"] for r in rows})
        }
        by_fn = {
            f"{lo:.2f}-{hi:.2f}": _stats(
                [r["oracles"][o].get("E_pct", float("nan")) for r in rows if lo <= r["Fn"] < hi]
            )
            for lo, hi in FN_BINS
        }
        per_oracle[o] = {
            "overall": _stats(errs),
            "by_hull": by_hull,
            "by_Fn": by_fn,
            "envelope": empirical_envelope(rows, o, envelope_tol_pct),
        }
    return {
        "schema": VALIDATION_SCHEMA,
        "reference": str(reference_path().relative_to(repo_root())),
        "convention": "E%D = (D - S)/D*100, model-scale C_T, C_F ITTC-57 at tank Re, no C_A",
        "envelope_tol_pct": envelope_tol_pct,
        "n_points": len(rows),
        "hulls": sorted({r["hull"] for r in rows}),
        "rows": rows,
        "per_oracle": per_oracle,
        "notes": (
            "Validation of this harness's oracles against public tank data. Small sample "
            f"({len(rows)} points, {len({r['hull'] for r in rows})} hulls): treat envelopes as "
            "evidence bounds, not certified validity ranges. Not ITTC V&V, not class."
        ),
    }


ENVELOPE_PARAMS = ("Fn", "Cb", "Cp", "L_B", "B_T", "lcb_frac")


def empirical_envelope(rows: Sequence[dict[str, Any]], oracle: str, tol_pct: float) -> dict[str, Any]:
    """Parameter box spanned by reference points where |E%D| <= tol (the validated set)."""
    ok = [r for r in rows if math.isfinite(r["oracles"][oracle].get("E_pct", float("nan")))
          and abs(r["oracles"][oracle]["E_pct"]) <= tol_pct]
    bad = [r for r in rows if math.isfinite(r["oracles"][oracle].get("E_pct", float("nan")))
           and abs(r["oracles"][oracle]["E_pct"]) > tol_pct]
    box = None
    if ok:
        box = {k: [min(r["params"][k] for r in ok), max(r["params"][k] for r in ok)] for k in ENVELOPE_PARAMS}
    return {
        "tol_pct": tol_pct,
        "n_validated": len(ok),
        "n_failed": len(bad),
        "validated_points": [f"{r['hull']}@Fn={r['Fn']:.3f}" for r in ok],
        "failed_points": [f"{r['hull']}@Fn={r['Fn']:.3f}" for r in bad],
        "box": box,
    }


# --------------------------------------------------- drift threshold derivation
def drift_threshold_from_validation(
    report: dict[str, Any],
    seen: str,
    holdout: str,
    *,
    quantile: float = 0.95,
    max_dFn: float = 0.06,
    same_hull_only: bool = False,
) -> dict[str, Any]:
    """Empirical default for the long-horizon drift flag between two oracles.

    The drift metric is ``|imp_seen - imp_holdout|`` with ``imp = (Ct_p - Ct_c)/Ct_p``.
    If each oracle's prediction is ``Ct_true * (1 - e)`` with relative error ``e``,
    then to first order ``imp_o = imp_true + (e_o(c) - e_o(p))`` and the expected
    oracle disagreement between a parent ``p`` and child ``c`` is
    ``|Δe_seen - Δe_holdout|``. We evaluate that on every ordered pair of
    measured reference points (different hulls or speeds, |ΔFn| <= max_dFn) and
    take the ``quantile``. A drift above it is larger than the two oracles'
    *measured* error structure explains on real hulls.
    """
    pts = []
    for r in report["rows"]:
        a, b = r["oracles"].get(seen, {}), r["oracles"].get(holdout, {})
        if "E_pct" in a and "E_pct" in b:
            pts.append((r["Fn"], a["E_pct"] / 100.0, b["E_pct"] / 100.0, r["hull"]))
    diffs = []
    for i, (fi, ai, bi, hi) in enumerate(pts):
        for j, (fj, aj, bj, hj) in enumerate(pts):
            if i == j or abs(fi - fj) > max_dFn or (same_hull_only and hi != hj):
                continue
            diffs.append(abs((aj - ai) - (bj - bi)))
    if not diffs:
        return {"seen": seen, "holdout": holdout, "threshold": None, "n_pairs": 0,
                "reason": "no reference pairs with both oracles available"}
    d = np.asarray(diffs)
    return {
        "seen": seen,
        "holdout": holdout,
        "threshold": float(np.quantile(d, quantile)),
        "quantile": quantile,
        "max_dFn": max_dFn,
        "same_hull_only": same_hull_only,
        "n_points": len(pts),
        "n_pairs": int(d.size),
        "median": float(np.median(d)),
        "max": float(d.max()),
        "method": "quantile of |Δe_seen − Δe_holdout| over reference-point pairs (first-order error propagation)",
    }


# ------------------------------------------------------------------ reporting
def render_markdown(report: dict[str, Any], drift: Sequence[dict[str, Any]] = ()) -> str:
    lines = [
        "# Oracle validation vs towing-tank data",
        "",
        f"Schema `{report['schema']}`. Reference: `{report['reference']}` "
        f"({report['n_points']} points, hulls: {', '.join(report['hulls'])}).",
        "",
        f"Convention: {report['convention']}. Positive E = oracle under-predicts.",
        "",
        "## Summary per oracle",
        "",
        "| oracle | n | mean E% | mean abs E% | RMS E% | max abs E% | validated pts (abs E <= "
        f"{report['envelope_tol_pct']:.0f}%) |",
        "|---|---|---|---|---|---|---|",
    ]
    for o, s in report["per_oracle"].items():
        ov = s["overall"]
        if not ov.get("n"):
            lines.append(f"| `{o}` | 0 | – | – | – | – | unavailable |")
            continue
        env = s["envelope"]
        lines.append(
            f"| `{o}` | {ov['n']} | {ov['mean_E_pct']:+.1f} | {ov['mean_abs_E_pct']:.1f} | {ov['rms_E_pct']:.1f} | "
            f"{ov['max_abs_E_pct']:.1f} | {env['n_validated']}/{env['n_validated'] + env['n_failed']} |"
        )
    lines += ["", "## Per point (E%D)", ""]
    names = list(report["per_oracle"])
    lines.append("| hull | Fn | Re | C_T meas ×10³ | " + " | ".join(f"`{o}`" for o in names) + " |")
    lines.append("|---|---|---|---|" + "---|" * len(names))
    for r in report["rows"]:
        cells = []
        for o in names:
            p = r["oracles"][o]
            cells.append(f"{p['CT']*1e3:.3f} ({p['E_pct']:+.1f}%)" if "E_pct" in p else "n/a")
        lines.append(f"| {r['hull']} | {r['Fn']:.3f} | {r['Re']:.2e} | {r['CT_measured']*1e3:.3f} | " + " | ".join(cells) + " |")
    lines += ["", "## Error by Froude band (mean abs E%)", ""]
    bands = list(next(iter(report["per_oracle"].values()))["by_Fn"])
    lines.append("| oracle | " + " | ".join(bands) + " |")
    lines.append("|---|" + "---|" * len(bands))
    for o, s in report["per_oracle"].items():
        cells = [(f"{v['mean_abs_E_pct']:.1f} (n={v['n']})" if v.get("n") else "–") for v in s["by_Fn"].values()]
        lines.append(f"| `{o}` | " + " | ".join(cells) + " |")
    lines += ["", "## Empirical validity envelopes", ""]
    for o, s in report["per_oracle"].items():
        env = s["envelope"]
        if env["box"] is None:
            lines.append(f"- `{o}`: no reference point within ±{env['tol_pct']:.0f}% — no validated envelope.")
            continue
        box = ", ".join(f"{k} [{v[0]:.3g}, {v[1]:.3g}]" for k, v in env["box"].items())
        lines.append(f"- `{o}`: {box}. Failed: {', '.join(env['failed_points']) or 'none'}.")
    if drift:
        lines += ["", "## Empirical drift thresholds (per oracle pair)", "",
                  "| seen | held-out | threshold | pairs | median | max |", "|---|---|---|---|---|---|"]
        for d in drift:
            if d.get("threshold") is None:
                lines.append(f"| `{d['seen']}` | `{d['holdout']}` | n/a | 0 | – | – |")
            else:
                lines.append(
                    f"| `{d['seen']}` | `{d['holdout']}` | {d['threshold']:.3f} | {d['n_pairs']} | "
                    f"{d['median']:.3f} | {d['max']:.3f} |"
                )
        lines += ["", f"Method: {drift[0].get('method', '')}; |ΔFn| <= {drift[0].get('max_dFn')}, "
                  f"q = {drift[0].get('quantile')}. Pairs span different hulls, so this is an upper-end "
                  "estimate for the small parent→child steps a search takes; the same-hull-only variant "
                  "(KCS speed pairs) is in the JSON under `drift_thresholds_same_hull`."]
    lines += ["", "## Caveats", "", report["notes"],
              "- Bulb, transom and C_WP are not tabulated by the sources and are omitted / estimated in `hm1984_full`.",
              "- `michell_l15` uses the gym's synthetic Wigley-like offsets, not the real hull lines.",
              "- Low-Fn points (Fn ≈ 0.1) carry larger tank uncertainty (3.2% for 5415)."]
    return "\n".join(lines) + "\n"


def write_reports(out_dir: str | Path, *, oracles: Iterable[str] = ORACLES) -> dict[str, Any]:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    rep = validate(oracles)
    pairs = [("hm1984_gym", "michell_l15"), ("hm1984_gym", "simplified_py"), ("hm1984_gym", "hm1984_full"),
             ("simplified_py", "michell_l15")]
    drift = [drift_threshold_from_validation(rep, a, b) for a, b in pairs
             if a in rep["per_oracle"] and b in rep["per_oracle"]]
    drift_same = [drift_threshold_from_validation(rep, a, b, same_hull_only=True) for a, b in pairs
                  if a in rep["per_oracle"] and b in rep["per_oracle"]]
    rep["drift_thresholds_same_hull"] = drift_same
    rep["drift_thresholds"] = drift
    (out / "oracle_tank_validation.json").write_text(json.dumps(rep, indent=2, sort_keys=True) + "\n")
    (out / "oracle_tank_validation.md").write_text(render_markdown(rep, drift))
    return rep


if __name__ == "__main__":  # pragma: no cover
    import sys

    r = write_reports(sys.argv[1] if len(sys.argv) > 1 else "reports/validation")
    for o, s in r["per_oracle"].items():
        print(o, s["overall"])
