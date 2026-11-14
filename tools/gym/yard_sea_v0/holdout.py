"""Held-out oracle check, surrogate-exploit flags, and long-horizon drift diagnostics.

The policy is trained/searched on its reward oracle (default L1 at design Fn).
After search, every final design is re-scored by a *held-out* oracle that never
entered the reward: by default L1 viscous + L1.5 Michell wave on a Froude grid
(``multi_froude_score(..., wave_oracle="michell")``). This catches designs that
exploit quirks of the cheap oracle.

* ``holdout_check``: rank agreement (Spearman), sign agreement, and per-design
  ``exploit`` flags (seen improvement > 0 but held-out improvement < -tol).
* ``trajectory_drift``: along one episode, compares the cheap oracle's cumulative
  improvement estimate with the held-out oracle's at every step, so error is
  judged on the long horizon, not just the first step.

The held-out oracle is *another model*, not ground truth. Swap in L2/L3 teachers
(``holdout_fn=``) when available; results are exploratory, not ITTC / class.
"""

from __future__ import annotations

import math
from typing import Any, Callable, Sequence

import numpy as np

from .hull import HullState
from .multi_froude import multi_froude_score
from .resistance_l1 import estimate_resistance

ScoreFn = Callable[[HullState, HullState], float]  # (child, parent) -> relative improvement


def seen_improvement(child: HullState, parent: HullState) -> float:
    """What the default policy reward saw: relative L1 Ct improvement at design Fn."""
    pc = estimate_resistance(parent).Ct
    return (pc - estimate_resistance(child).Ct) / pc


def make_holdout_fn(fn_grid: Sequence[float] | None = None, wave_oracle: str = "michell") -> ScoreFn:
    def f(child: HullState, parent: HullState) -> float:
        out = multi_froude_score(child, parent, fn_grid, wave_oracle=wave_oracle, worst_case_weight=0.0)
        return float("nan") if out["score"] is None else float(out["mean_d_total"])

    f.__name__ = f"holdout_multi_froude_{wave_oracle}"
    return f


def _rank(x: np.ndarray) -> np.ndarray:
    order = np.argsort(x, kind="mergesort")
    r = np.empty(len(x), dtype=float)
    r[order] = np.arange(len(x), dtype=float)
    # average ties
    for v in np.unique(x):
        m = x == v
        if m.sum() > 1:
            r[m] = r[m].mean()
    return r


def spearman(a: Sequence[float], b: Sequence[float]) -> float | None:
    x, y = np.asarray(a, float), np.asarray(b, float)
    ok = np.isfinite(x) & np.isfinite(y)
    x, y = x[ok], y[ok]
    if len(x) < 3:
        return None
    rx, ry = _rank(x), _rank(y)
    if rx.std() == 0 or ry.std() == 0:
        return None
    return float(np.corrcoef(rx, ry)[0, 1])


def holdout_check(
    designs: Sequence[HullState],
    parent: HullState,
    *,
    seen_fn: ScoreFn = seen_improvement,
    holdout_fn: ScoreFn | None = None,
    exploit_tol: float = 0.0,
) -> dict[str, Any]:
    holdout_fn = holdout_fn or make_holdout_fn()
    rows = []
    for i, d in enumerate(designs):
        s, h = float(seen_fn(d, parent)), float(holdout_fn(d, parent))
        rows.append(
            {
                "index": i,
                "seen": s,
                "holdout": h,
                "gap": s - h if math.isfinite(h) else None,
                "confirmed": s > 0 and math.isfinite(h) and h > 0,
                "exploit": s > 0 and math.isfinite(h) and h < -exploit_tol,
                "hull": d.to_dict(),
            }
        )
    seen = [r["seen"] for r in rows]
    hold = [r["holdout"] for r in rows]
    finite = [r for r in rows if math.isfinite(r["holdout"])]
    claimed = [r for r in finite if r["seen"] > 0]
    return {
        "schema": "yard_sea_v0.holdout.v1",
        "holdout_oracle": getattr(holdout_fn, "__name__", "holdout"),
        "seen_oracle": getattr(seen_fn, "__name__", "seen"),
        "n": len(rows),
        "spearman": spearman(seen, hold),
        "sign_agreement": (
            sum((r["seen"] > 0) == (r["holdout"] > 0) for r in finite) / len(finite) if finite else None
        ),
        "n_claimed": len(claimed),
        "n_confirmed": sum(r["confirmed"] for r in rows),
        "n_exploit": sum(r["exploit"] for r in rows),
        "exploit_rate": (sum(r["exploit"] for r in claimed) / len(claimed)) if claimed else None,
        "rows": rows,
        "notes": "Held-out oracle never enters the reward. It is a second model, not ground truth.",
    }


def trajectory_drift(
    states: Sequence[HullState],
    parent: HullState,
    *,
    seen_fn: ScoreFn = seen_improvement,
    holdout_fn: ScoreFn | None = None,
) -> dict[str, Any]:
    """Per-step |seen - holdout| along an episode (long-horizon, not next-step only)."""
    holdout_fn = holdout_fn or make_holdout_fn()
    errs, seen, hold = [], [], []
    for st in states:
        s, h = float(seen_fn(st, parent)), float(holdout_fn(st, parent))
        seen.append(s)
        hold.append(h)
        errs.append(abs(s - h) if math.isfinite(h) else float("nan"))
    e = np.asarray(errs, float)
    ok = np.isfinite(e)
    slope = None
    if ok.sum() >= 2:
        t = np.arange(len(e))[ok]
        slope = float(np.polyfit(t, e[ok], 1)[0])
    first = float(e[ok][0]) if ok.any() else None
    last = float(e[ok][-1]) if ok.any() else None
    return {
        "schema": "yard_sea_v0.drift.v1",
        "n_steps": len(states),
        "abs_error": errs,
        "seen": seen,
        "holdout": hold,
        "first_step_error": first,
        "final_error": last,
        "max_error": float(np.nanmax(e)) if ok.any() else None,
        "error_slope_per_step": slope,
        "growth_ratio": (last / first) if first and last is not None and first > 0 else None,
        "notes": "Report final/max error and slope; first-step error alone understates drift.",
    }


def states_from_evidence(packs: Sequence[dict[str, Any]]) -> list[HullState]:
    keys = ("L", "B", "T", "Cb", "lcb_frac", "kg_frac", "Fn")
    out = []
    for p in packs:
        if p.get("type") == "claim" or not p.get("monitor", {}).get("allow"):
            continue
        h = p.get("hull") or {}
        if all(k in h for k in keys):
            out.append(HullState(**{k: h[k] for k in keys}))
    return out
