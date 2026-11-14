"""Fast forward-speed added resistance in head waves: STAwave-2 (``stawave2_v0``).

Empirical transfer function of the mean resistance increase in regular head
waves from ITTC Recommended Procedure 7.5-04-01-01.2 (2014, rev. 01), Annex D.2
(STA-JIP), reproduced here from the public procedure:

* motion-induced  ``R_AWM = 4 ρ g ζa² (B²/L) r̄aw(ω̄)``,
  ``r̄aw = ω̄^b1 · exp[(b1/d1)(1 − ω̄^d1)] · a1 · Fr^1.50 · exp(−3.50 Fr)``,
  ``ω̄ = sqrt(L/g) · k_yy^(1/3) / (1.17 Fr^−0.143) · ω``, ``a1 = 60.3 C_B^1.34``,
  ``b1 = 11.0`` (ω̄ < 1) else ``−8.50``; ``d1 = 14.0`` (ω̄ < 1) else ``−566 (L/B)^−2.66``
* reflection      ``R_AWR = ½ ρ g ζa² B α1(ω)``,
  ``α1 = π² I1²(1.5kT) / (π² I1²(1.5kT) + K1²(1.5kT)) · f1``,
  ``f1 = 0.692 (V / sqrt(T g))^0.769 + 1.81 C_B^6.95``

The procedure's stated range of application is checked and reported
(75 ≤ L ≤ 350 m, 4.0 ≤ L/B ≤ 9.0, 2.2 ≤ B/T ≤ 5.5, 0.10 ≤ Fr ≤ 0.30,
0.50 ≤ C_B ≤ 0.90, head waves within ±45°). Outside it the number is still
returned but flagged and not credited by the reward. ``k_yy = 0.25`` (fraction
of L) is a convention. Irregular seas: ``R̄aw = 2∫S(ω) R_aw(ω)/ζa² dω`` with the
two-parameter spectrum from ``seakeeping.SeaState``.

Used here as a fast (µs) ranking term inside the RL reward; Capytaine
(``seakeeping.py``, zero speed) stays a search-time / held-out cross-check.
This is an empirical regression for merchant hull forms, not a seakeeping
prediction for an arbitrary hull, not a speed-trial correction, and not class.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any, Sequence

import numpy as np

from .hull import G, RHO_SW, HullState
from .seakeeping import EXAMPLE_SEA_STATE, SeaState

LABEL = "stawave2_v0"
SOURCE = "ITTC 7.5-04-01-01.2 (2014 rev 01) Annex D.2, STAwave-2 (STA-JIP)"
KYY_CONVENTION = 0.25
OMEGA_GRID = np.linspace(0.05, 4.0, 800)
VALIDITY = {"L": (75.0, 350.0), "L_B": (4.0, 9.0), "B_T": (2.2, 5.5), "Fr": (0.10, 0.30), "Cb": (0.50, 0.90)}


def validity(h: HullState, Fr: float | None = None) -> dict[str, Any]:
    fr = h.Fn if Fr is None else Fr
    vals = {"L": h.L, "L_B": h.L / h.B, "B_T": h.B / h.T, "Fr": fr, "Cb": h.Cb}
    out = {k: VALIDITY[k][0] <= v <= VALIDITY[k][1] for k, v in vals.items()}
    return {"within": all(out.values()), "checks": out, "values": vals, "ranges": VALIDITY}


def raw_components(h: HullState, omega: Sequence[float] | float, Fr: float | None = None, *,
                   kyy: float = KYY_CONVENTION, rho: float = RHO_SW) -> dict[str, np.ndarray]:
    """Per-ζa² transfer functions [N/m²]: motion, reflection, total (head waves)."""
    from scipy.special import i1, k1

    w = np.atleast_1d(np.asarray(omega, dtype=float))
    fr = float(h.Fn if Fr is None else Fr)
    L, B, T, cb = float(h.L), float(h.B), float(h.T), float(h.Cb)
    V = fr * math.sqrt(G * L)
    a1 = 60.3 * cb**1.34
    if fr > 0:
        wbar = math.sqrt(L / G) * kyy ** (1.0 / 3.0) / (1.17 * fr ** -0.143) * w
        lo = wbar < 1.0
        b1 = np.where(lo, 11.0, -8.50)
        d1 = np.where(lo, 14.0, -566.0 * (L / B) ** -2.66)
        with np.errstate(over="ignore", divide="ignore", invalid="ignore"):
            r = wbar**b1 * np.exp((b1 / d1) * (1.0 - wbar**d1)) * a1 * fr**1.50 * math.exp(-3.50 * fr)
        r = np.nan_to_num(r, nan=0.0, posinf=0.0)
    else:
        r = np.zeros_like(w)
    motion = 4.0 * rho * G * B**2 / L * r
    k = w**2 / G
    x = 1.5 * k * T
    with np.errstate(over="ignore", invalid="ignore"):
        I, K = i1(x), k1(x)
        alpha_t = np.where(np.isfinite(I**2), (math.pi**2 * I**2) / (math.pi**2 * I**2 + K**2), 1.0)
    f1 = 0.692 * (V / math.sqrt(T * G)) ** 0.769 + 1.81 * cb**6.95
    refl = 0.5 * rho * G * B * alpha_t * f1
    return {"omega": w, "motion": motion, "reflection": refl, "total": motion + refl, "f1": f1}


def mean_added_resistance(h: HullState, sea: SeaState = EXAMPLE_SEA_STATE, Fr: float | None = None,
                          *, kyy: float = KYY_CONVENTION) -> dict[str, Any]:
    c = raw_components(h, OMEGA_GRID, Fr, kyy=kyy)
    S = sea.spectrum(OMEGA_GRID)
    tot = 2.0 * float(np.trapezoid(S * c["total"], OMEGA_GRID))
    mot = 2.0 * float(np.trapezoid(S * c["motion"], OMEGA_GRID))
    return {"label": LABEL, "source": SOURCE, "sea_state": sea.to_dict(),
            "Fr": float(h.Fn if Fr is None else Fr), "mean_raw_N": tot, "motion_N": mot,
            "reflection_N": tot - mot,
            "spectral_coverage": float(np.trapezoid(S, OMEGA_GRID)) / sea.m0(),
            "validity": validity(h, Fr), "kyy_convention": kyy}


@dataclass(frozen=True)
class SeaCondition:
    name: str
    weight: float
    sea: SeaState | None  # None = calm water


DEFAULT_SEA_CONDITIONS = (SeaCondition("calm", 1.0, None),
                          SeaCondition(EXAMPLE_SEA_STATE.name, 1.0, EXAMPLE_SEA_STATE))


def sea_state_totals(h: HullState, conditions: Sequence[SeaCondition] = DEFAULT_SEA_CONDITIONS) -> list[dict[str, Any]]:
    from .acceptance import accept_l1
    from .resistance_l1 import estimate_resistance

    r = estimate_resistance(h)
    acc = accept_l1(r)
    rows = []
    for c in conditions:
        row: dict[str, Any] = {"name": c.name, "weight": c.weight, "calm_Rt_N": float(r.Rt_N),
                               "failed_checks": list(acc.failed_checks)}
        if c.sea is None:
            row["total_N"] = float(r.Rt_N)
        else:
            m = mean_added_resistance(h, c.sea)
            row.update({"mean_raw_N": m["mean_raw_N"], "motion_N": m["motion_N"],
                        "total_N": float(r.Rt_N) + m["mean_raw_N"], "validity": m["validity"]})
            if not m["validity"]["within"]:
                row["failed_checks"].append("stawave2_outside_validity")
        row["accepted"] = not row["failed_checks"]
        rows.append(row)
    return rows


def sea_state_score(child: HullState, parent: HullState,
                    conditions: Sequence[SeaCondition] = DEFAULT_SEA_CONDITIONS, *,
                    worst_case_weight: float = 1.0) -> dict[str, Any]:
    """Relative improvement across calm + sea conditions (fast; usable per RL step)."""
    cr, pr = sea_state_totals(child, conditions), sea_state_totals(parent, conditions)
    rows = []
    for c, a, b in zip(conditions, cr, pr):
        ok = a["accepted"] and b["accepted"] and b["total_N"] > 0
        rows.append({"name": c.name, "weight": c.weight, "credited": ok,
                     "d_total": (b["total_N"] - a["total_N"]) / b["total_N"] if ok else None,
                     "child": a, "parent": b})
    cred = [r for r in rows if r["credited"]]
    out = {"label": LABEL, "points": rows, "n_credited": len(cred), "accepted": len(cred) == len(rows)}
    if not cred:
        return {**out, "score": None}
    ws = sum(r["weight"] for r in cred) or 1.0
    mean = sum(r["weight"] * r["d_total"] for r in cred) / ws
    worst = min(r["d_total"] for r in cred)
    return {**out, "score": mean + worst_case_weight * min(0.0, worst), "mean_d_total": mean,
            "worst_d_total": worst}


def crosscheck_capytaine(h: HullState, sea: SeaState = EXAMPLE_SEA_STATE, *,
                         solve_kwargs: dict[str, Any] | None = None) -> dict[str, Any]:
    """Zero-speed Capytaine far-field drift vs STAwave-2 (labelled comparison, not validation).

    STAwave-2's motion term vanishes as Fr → 0 and the method is only stated for
    Fr ≥ 0.10, so two STAwave-2 numbers are reported: the reflection term at V = 0
    (comparable in kind to the short-wave end of Capytaine's zero-speed drift),
    and the full STAwave-2 at Fr = 0.10 and at the hull's Fn.
    """
    from .seakeeping import solve, spectral_added_resistance

    sol = solve(h, **(solve_kwargs or {}))
    if sol.get("skipped"):
        return {"available": False, "reason": sol.get("skip_reason")}
    om = np.asarray(sol["omega"])
    cap = np.asarray(sol["raw_per_zeta2_N_m2"])
    s0 = raw_components(h, om, 0.0)
    cap_mean = spectral_added_resistance(sol, sea)["mean_added_resistance_N"]
    st_fn = mean_added_resistance(h, sea)
    st_010 = mean_added_resistance(h, sea, 0.10)
    return {
        "available": True, "sea_state": sea.to_dict(),
        "short_wave_ratio_capytaine_over_stawave_reflection_V0": float(cap[-1] / s0["reflection"][-1]),
        "capytaine_zero_speed_mean_N": cap_mean,
        "stawave2_Fr0.10_mean_N": st_010["mean_raw_N"], "stawave2_design_Fn_mean_N": st_fn["mean_raw_N"],
        "ratio_stawave_design_over_capytaine0": st_fn["mean_raw_N"] / cap_mean if cap_mean > 0 else None,
        "notes": "Different physics (zero-speed potential flow vs forward-speed regression); comparison only.",
    }
