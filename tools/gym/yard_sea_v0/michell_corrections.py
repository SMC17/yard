"""Michell on the real hull lines with published viscous / transom corrections (yard round-3 item 5).

``validation.michell_lines`` = ITTC-57 C_F x (1+k from the gym HM1984 form factor) + Michell R_W on the
real lines. This module tests whether two published corrections bring it to the tank data:

* Viscous form factor (1+k), Watanabe's correlation, as quoted by e.g. Pullen (MIT 2014,
  hdl.handle.net/1721.1/85527):  k = -0.095 + 25.6 C_B / ((L/B)^2 sqrt(B/T)).
* Transom (Doctors & Day 1997, FAST'97; Doctors 2006, IWWWFB 21 "Influence of the transom-hollow
  length on wave resistance"): Michell is applied to the hull *plus a virtual appendage* behind the
  transom, which removes the source discontinuity of an open stern section. Doctors (2006) found
  the effective hollow length is never less than 6.680 x the transom draft T_T (backward-facing-step
  dead-water length). The regression coefficients for the full hollow length are not published in that
  abstract, so the **appendage length is set to that minimum, 6.680 T_T (convention)**. Its
  depth recedes along the parabola Doctors fitted to the hollow, d(s) = T_T (1 - s)^2,
  s = distance aft / hollow length.
  The pressure deficit on the transom is the HM1984 term R_TR = 0.5 rho U^2 A_T c_6, with
  c_6 = 0.2 (1 - 0.2 F_nT) for F_nT < 5 and 0 otherwise. Doctors & Day's fully dry hydrostatic term
  over-predicts at low speed (Doctors 2006, Fig. 5 "Full"), and every tank point here has F_nT <= 9.
  The transom section is taken 0.002 L inside the aft end, the same convention ``hull_lines`` uses for
  A_T. The correction is applied only to hulls whose lines have a transom (``_FRAME['transom']``).
  KVLCC2's open aft section is a truncation of the stern offsets, not a transom, so it is reported as
  a sensitivity only.

An applicability envelope is set only if the corrected oracle validates (mean |E| <= tol at the
standard tolerance). Otherwise it stays unvalidated, and this report says so.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

import numpy as np

from . import validation as v

HOLLOW_MIN_OVER_TT = 6.680  # Doctors (2006): minimal effective hollow length / transom draft
TRANSOM_SECTION_CUT = 0.002  # x / Lpp inside the aft end, as hull_lines.particulars A_T
SCHEMA = "yard_sea_v0.michell_corrections.v1"
# The appendage is only ~1.4 % L long for 5415, so the transom variants need a finer grid than
# MICHELL_LINES_GRID: 481x61 is within ~3 % of 961x61 in R_W (5415, Fn 0.10-0.41; checked by hand).
TRANSOM_GRID = {"nx": 481, "nz": 61, "n_theta": 60}


def watanabe_form_factor(L: float, B: float, T: float, Cb: float) -> float:
    """1 + k, Watanabe: k = -0.095 + 25.6 Cb / ((L/B)^2 sqrt(B/T))."""
    return 1.0 + (-0.095 + 25.6 * Cb / ((L / B) ** 2 * math.sqrt(B / T)))


def hm1984_transom_c6(fn_t: float) -> float:
    return 0.2 * (1.0 - 0.2 * fn_t) if fn_t < 5.0 else 0.0


def lines_offsets(hull: str, L: float, nx: int, nz: int, cut: float = 0.0
                  ) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Michell (Y, X, Z) on the real lines starting ``cut`` x Lpp inside the aft end, scaled to Lpp = L."""
    from . import hull_lines as h

    if cut == 0.0:
        return h.michell_offsets(hull, scale_to_L=L, nx=nx, nz=nz)
    p = h.particulars(hull)
    nx += 1 - nx % 2
    zwl = p.z_keel + p.T
    g = np.concatenate([s.reshape(-1, 3) for s in h.surface(hull)])
    zbot = float(g[g[:, 2] <= zwl][:, 2].min())
    x0 = p.x_aft + cut * p.Lpp
    xs, zs = np.linspace(x0, p.x_fwd, nx), np.linspace(zwl, zbot, nz)
    k = L / p.Lpp
    return h.halfbreadth(hull, xs, zs) * k, (xs - x0) * k, (zs - zwl) * k


def transom_section(Y: np.ndarray, Z: np.ndarray, L: float) -> dict[str, float]:
    yt = Y[0]
    wet = yt > 1e-6 * L
    a_t = 2.0 * float(np.trapezoid(yt, -Z))
    t_t = abs(float((-Z[wet]).max())) if wet.any() else 0.0
    return {"A_T": a_t, "T_T": t_t}


def add_virtual_appendage(Y: np.ndarray, X: np.ndarray, Z: np.ndarray, length: float, t_t: float
                          ) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Prepend stations aft of X[0] (same spacing, even count so nx stays odd for Filon): the transom
    section is continued where |z| <= t_t (1 - s)^2, and is zero below that."""
    dx = float(X[1] - X[0])
    n = int(math.ceil(length / dx)) if length > 0 else 0
    n += n % 2
    if n == 0:
        return Y, X, Z
    xa = -dx * np.arange(n, 0, -1)
    s = -xa / length
    ya = np.array([np.where(-Z <= t_t * max(0.0, 1.0 - si) ** 2 + 1e-12, Y[0], 0.0) for si in s])
    return np.vstack([ya, Y]), np.concatenate([xa, X]) - xa[0], Z


def _rw_over_q(c: v.TankCase, Y, X, Z, g: dict[str, int]) -> float | None:
    from .teachers import michell_l15 as mich

    m = mich.run(c.hull_state(appendages=False), Y=Y, X=X, Z=Z, n_theta=g["n_theta"])
    if m.get("skipped") or m.get("Rw_N") is None:
        return None
    U = float(m["U"])
    return float(m["Rw_N"]) / (0.5 * 1025.0 * U * U)


def michell_lines_corrected(c: v.TankCase, *, form_factor: str = "watanabe", transom: bool = True,
                            force_transom: bool = False, hollow_scale: float = 1.0) -> dict[str, Any]:
    """C_T = C_F (1+k) + R_W/(q S0) [Michell, real lines (+ virtual appendage)] + C_TR [HM1984]."""
    from . import hull_lines as h

    if c.hull not in v._LINES_LPP or not h.available(c.hull):
        return {"available": False, "reason": "no hull lines for this hull (fetch or not supported)"}
    if form_factor == "watanabe":
        opk = watanabe_form_factor(c.L, c.B, c.T, c.Cb)
    elif form_factor == "hm1984_gym":
        gym, r = v._gym_l1(c, prefer_zig=True, appendages=False)
        if not gym.get("available"):
            gym, r = v._gym_l1(c, prefer_zig=False, appendages=False)
        opk = 1.0 + float(r.k1)
    else:
        raise ValueError(form_factor)
    has_transom = bool(h._FRAME[c.hull]["transom"]) or force_transom
    use_tr = transom and has_transom
    g = TRANSOM_GRID if use_tr else v.MICHELL_LINES_GRID
    Y, X, Z = lines_offsets(c.hull, c.L, g["nx"], g["nz"], TRANSOM_SECTION_CUT if use_tr else 0.0)
    tr: dict[str, Any] = {"applied": use_tr}
    c_tr = 0.0
    if use_tr:
        sec = transom_section(Y, Z, c.L)
        # T_T = 0: the transom section is wet only at the waterline row (immersion below grid resolution).
        fn_t = c.U / math.sqrt(c.g * sec["T_T"]) if sec["T_T"] > 0 else None
        lh = hollow_scale * HOLLOW_MIN_OVER_TT * sec["T_T"]
        Y, X, Z = add_virtual_appendage(Y, X, Z, lh, sec["T_T"])
        c6 = hm1984_transom_c6(fn_t) if fn_t is not None else 0.0
        c_tr = c6 * sec["A_T"] / c.S0
        tr.update(A_T_m2=sec["A_T"], T_T_m=sec["T_T"], Fn_T=fn_t, hollow_length_m=lh, c_6=c6, C_TR=c_tr)
    rwq = _rw_over_q(c, Y, X, Z, g)
    if rwq is None:
        return {"available": False, "reason": "michell_failed"}
    cf = float(v.ittc57_cf(c.Re))
    ct = cf * opk + rwq / c.S0 + c_tr
    return {"available": True, "CT": ct, "C_F": cf, "one_plus_k": opk, "form_factor": form_factor,
            "Cw_S0": rwq / c.S0, "transom": tr, "grid": dict(g)}


VARIANTS = {
    "baseline (HM 1+k, open stern)": dict(form_factor="hm1984_gym", transom=False),
    "Watanabe 1+k": dict(form_factor="watanabe", transom=False),
    "HM 1+k + transom (Doctors appendage + HM R_TR)": dict(form_factor="hm1984_gym", transom=True),
    "Watanabe 1+k + transom": dict(form_factor="watanabe", transom=True),
}
PRIMARY = "Watanabe 1+k + transom"


def analyse(tol_pct: float = v.DEFAULT_ENVELOPE_TOL_PCT) -> dict[str, Any]:
    cases = [c for c in v.tank_cases() if c.hull in v._LINES_LPP]
    rows = []
    for c in cases:
        row = {"hull": c.hull, "Fn": c.Fn, "CT_measured": c.CT, "params": c.params(), "oracles": {}}
        for name, kw in VARIANTS.items():
            p = michell_lines_corrected(c, **kw)
            if p.get("available"):
                p["E_pct"] = v.comparison_error_pct(c.CT, p["CT"])
            row["oracles"][name] = p
        rows.append(row)
    stats = {n: v._stats([r["oracles"][n].get("E_pct", float("nan")) for r in rows]) for n in VARIANTS}
    for n in VARIANTS:
        stats[n]["n_within_tol"] = sum(1 for r in rows if abs(r["oracles"][n].get("E_pct", math.inf)) <= tol_pct)
    sens = []
    for c in cases:
        if c.hull == "DTMB5415":
            for hs in (0.5, 2.0):
                p = michell_lines_corrected(c, hollow_scale=hs)
                sens.append({"case": f"{c.hull}@Fn={c.Fn:.3f}", "what": f"hollow length x{hs}",
                             "E_pct": v.comparison_error_pct(c.CT, p["CT"]), "Cw_S0": p["Cw_S0"]})
        if c.hull == "KVLCC2":
            p = michell_lines_corrected(c, force_transom=True)
            sens.append({"case": f"{c.hull}@Fn={c.Fn:.3f}", "what": "truncated stern closed as if a transom",
                         "E_pct": v.comparison_error_pct(c.CT, p["CT"]), "Cw_S0": p["Cw_S0"]})
    prim = stats[PRIMARY]
    validated = bool(prim.get("n")) and prim["mean_abs_E_pct"] <= tol_pct
    env = v.empirical_envelope(rows, PRIMARY, tol_pct) if validated else None
    return {"schema": SCHEMA, "tol_pct": tol_pct, "primary": PRIMARY, "rows": rows, "stats": stats,
            "sensitivity": sens, "validated": validated, "envelope": env,
            "conventions": {"hollow_length": f"{HOLLOW_MIN_OVER_TT} T_T (Doctors 2006 minimum; full regression not used)",
                            "transom_section": f"{TRANSOM_SECTION_CUT} Lpp inside aft end (hull_lines A_T convention)",
                            "grid": f"open stern {v.MICHELL_LINES_GRID}, transom variants {TRANSOM_GRID}",
                            "appendage_depth": "T_T (1 - s)^2 parabola (Doctors hollow shape)",
                            "transom_drag": "HM1984 c_6 (wet/partially ventilated); Doctors-Day dry hydrostatic not used"}}


def render_markdown(r: dict[str, Any]) -> str:
    names = list(VARIANTS)
    L = ["# Michell on real hull lines: published viscous / transom corrections", "",
         "E% = (D - S)/D (negative = over-prediction). Model scale, ITTC-57 C_F at tank Re. "
         f"Validation tolerance ±{r['tol_pct']:.0f}% (the harness default).", "",
         "## Summary", "", "| variant | n | mean E% | mean abs E% | max abs E% | within tol |", "|---|---|---|---|---|---|"]
    for n in names:
        s = r["stats"][n]
        L.append(f"| {n} | {s['n']} | {s['mean_E_pct']:+.1f} | {s['mean_abs_E_pct']:.1f} | {s['max_abs_E_pct']:.1f} | "
                 f"{s['n_within_tol']}/{s['n']} |")
    L += ["", "## Per point (C_T x10^3, E%)", "", "| hull | Fn | meas | " + " | ".join(names) + " | 1+k HM / Wat. | C_W/S0 open / +app. |",
          "|---|---|---|" + "---|" * len(names) + "---|---|"]
    for row in r["rows"]:
        o = row["oracles"]
        cells = [f"{o[n]['CT'] * 1e3:.3f} ({o[n]['E_pct']:+.1f}%)" for n in names]
        a, b = o[names[0]], o[PRIMARY]
        L.append(f"| {row['hull']} | {row['Fn']:.3f} | {row['CT_measured'] * 1e3:.3f} | " + " | ".join(cells)
                 + f" | {a['one_plus_k']:.3f} / {b['one_plus_k']:.3f} | {a['Cw_S0']:.2e} / {b['Cw_S0']:.2e} |")
    L += ["", "## Transom inputs (model scale, from the lines)", "", "| hull | Fn | A_T m² | T_T m | F_nT | hollow m | c_6 | C_TR |",
          "|---|---|---|---|---|---|---|---|"]
    for row in r["rows"]:
        t = row["oracles"][PRIMARY]["transom"]
        if t.get("applied"):
            fnt = "n/a (T_T below grid)" if t["Fn_T"] is None else f"{t['Fn_T']:.2f}"
            L.append(f"| {row['hull']} | {row['Fn']:.3f} | {t['A_T_m2']:.2e} | {t['T_T_m']:.4f} | {fnt} | "
                     f"{t['hollow_length_m']:.3f} | {t['c_6']:.3f} | {t['C_TR']:.2e} |")
    L += ["", "## Sensitivity", "", "| case | change | E% | C_W/S0 |", "|---|---|---|---|"]
    for s in r["sensitivity"]:
        L.append(f"| {s['case']} | {s['what']} | {s['E_pct']:+.1f} | {s['Cw_S0']:.2e} |")
    base, prim = r["stats"][names[0]], r["stats"][PRIMARY]
    L += ["", "## Finding", "",
          f"- Mean |E| goes from {base['mean_abs_E_pct']:.1f}% (baseline) to {prim['mean_abs_E_pct']:.1f}% "
          f"(Watanabe 1+k + transom); {prim['n_within_tol']}/{prim['n']} points are within ±{r['tol_pct']:.0f}%.",
          "- The corrections act on the wrong term. The residual is Michell's own over-prediction of R_W on "
          "blunt real hull forms (C_W/S0 alone is about the size of the measured C_T at KCS Fn 0.26, KVLCC2 "
          "and 5415 Fn 0.10). A form factor only moves the viscous term by a few percent, and the "
          "transom appendage only helps 5415 at low speed.",
          ("- **Validated**: envelope set from the passing points." if r["validated"] else
           "- **Not validated, so no envelope is set.** `michell_lines` stays without an applicability envelope "
           "on real hull forms, and the corrections are exposed here as a study, not as a gym oracle."),
          "", "Conventions: " + "; ".join(f"{k}: {x}" for k, x in r["conventions"].items()) + "."]
    return "\n".join(L) + "\n"


def write_reports(out_dir: str | Path = "reports/validation") -> dict[str, Any]:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    r = analyse()
    (out / "michell_corrections.json").write_text(json.dumps(r, indent=1, sort_keys=True, default=float) + "\n")
    (out / "michell_corrections.md").write_text(render_markdown(r))
    return r


if __name__ == "__main__":
    import sys

    write_reports(sys.argv[1] if len(sys.argv) > 1 else "reports/validation")
