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

Selectable held-out oracles (``make_holdout_fn(oracle=...)``, CLI ``--holdout-oracle``):

* ``michell``       — L1 viscous + Michell L1.5 thin-ship wave, Froude grid (default).
* ``hm1984``        — Zig Holtrop-Mennen 1984 L1 on the Froude grid. Unavailable
                      (NaN rows, ``available=False``) when ``zig_gym`` is not built;
                      never silently falls back to the Python L1.
* ``capytaine_l2``  — Capytaine linear BEM on an L×B×T parallelepiped at design Fn
                      (radiation-damping wave proxy). It cannot see Cb / lcb / kg:
                      designs that differ from the parent only there are marked
                      ``blind`` instead of being scored 0.

Every oracle carries ``wave_model`` and ``sensitive_to``. ``holdout_check``
reports ``independent_of_seen`` = the held-out wave model differs from the one
that produced the seen improvement; an oracle that shares it is not held out.

The held-out oracle is *another model*, not ground truth. Results are
exploratory, not ITTC / class.
"""

from __future__ import annotations

import dataclasses
import math
from typing import Any, Callable, Sequence

import numpy as np

from .hull import HullState
from .multi_froude import multi_froude_score
from .resistance_l1 import estimate_resistance

ScoreFn = Callable[[HullState, HullState], float]  # (child, parent) -> relative improvement


HULL_KEYS = ("L", "B", "T", "Cb", "lcb_frac", "kg_frac", "Fn")
HOLDOUT_ORACLES = ("michell", "hm1984", "capytaine_l2")


def seen_improvement(child: HullState, parent: HullState) -> float:
    """What the default policy reward saw: relative L1 Ct improvement at design Fn."""
    pc = estimate_resistance(parent).Ct
    return (pc - estimate_resistance(child).Ct) / pc


def seen_wave_model(parent: HullState) -> str:
    """Wave model behind ``seen_improvement`` (the L1 fidelity tag, e.g. hm1984_zig)."""
    return str(estimate_resistance(parent).fidelity)


seen_improvement.wave_model_for = seen_wave_model  # type: ignore[attr-defined]


def _rel(pc: float, cc: float) -> float:
    if not (math.isfinite(pc) and math.isfinite(cc)) or pc <= 0:
        return float("nan")
    return (pc - cc) / pc


def _hm1984_fn(fn_grid: Sequence[float] | None) -> ScoreFn:
    from .multi_froude import fn_grid_for
    from .zig_bridge import estimate_resistance_zig, zig_available

    avail = zig_available()

    def ct(h: HullState) -> float:
        return float(estimate_resistance_zig(h, fidelity="hm1984").Ct)

    def f(child: HullState, parent: HullState) -> float:
        if not avail:
            return float("nan")
        grid = tuple(fn_grid) if fn_grid else fn_grid_for(parent)
        vals = []
        for fn in grid:
            try:
                vals.append(_rel(ct(dataclasses.replace(parent, Fn=fn)), ct(dataclasses.replace(child, Fn=fn))))
            except Exception:
                vals.append(float("nan"))
        ok = [v for v in vals if math.isfinite(v)]
        return float(np.mean(ok)) if ok and len(ok) == len(vals) else float("nan")

    f.available = avail  # type: ignore[attr-defined]
    f.unavailable_reason = None if avail else "zig_gym binary not built"  # type: ignore[attr-defined]
    return f


def _capytaine_fn() -> ScoreFn:
    from .teachers import panel_l2

    av = panel_l2.detect()

    def ct(h: HullState) -> float:
        r = panel_l2.run(h, availability=av)
        return float("nan") if r.get("skipped") else float(r["Ct"])

    def f(child: HullState, parent: HullState) -> float:
        if not av.available:
            return float("nan")
        # Compare at the parent's design speed so only geometry differs.
        return _rel(ct(parent), ct(dataclasses.replace(child, Fn=parent.Fn)))

    f.available = av.available  # type: ignore[attr-defined]
    f.unavailable_reason = None if av.available else (av.error or "capytaine missing")  # type: ignore[attr-defined]
    return f


def make_holdout_fn(
    fn_grid: Sequence[float] | None = None,
    wave_oracle: str = "michell",
    *,
    oracle: str | None = None,
) -> ScoreFn:
    """Build a held-out score fn. ``oracle`` (one of ``HOLDOUT_ORACLES``) wins over ``wave_oracle``."""
    name = oracle or ("michell" if wave_oracle == "michell" else None)
    if oracle is not None and oracle not in HOLDOUT_ORACLES:
        raise ValueError(f"holdout oracle must be one of {HOLDOUT_ORACLES}")
    if name == "hm1984":
        f = _hm1984_fn(fn_grid)
        f.__name__ = "holdout_multi_froude_hm1984_zig"
        f.wave_model = "hm1984_zig"  # type: ignore[attr-defined]
        f.sensitive_to = HULL_KEYS  # type: ignore[attr-defined]
        return f
    if name == "capytaine_l2":
        f = _capytaine_fn()
        f.__name__ = "holdout_capytaine_l2_box"
        f.wave_model = "capytaine_l2_box"  # type: ignore[attr-defined]
        f.sensitive_to = ("L", "B", "T")  # type: ignore[attr-defined]
        return f

    def f(child: HullState, parent: HullState) -> float:
        out = multi_froude_score(child, parent, fn_grid, wave_oracle=wave_oracle, worst_case_weight=0.0)
        return float("nan") if out["score"] is None else float(out["mean_d_total"])

    f.__name__ = f"holdout_multi_froude_{wave_oracle}"
    f.wave_model = "michell_l15" if wave_oracle == "michell" else None  # type: ignore[attr-defined]
    f.sensitive_to = HULL_KEYS  # type: ignore[attr-defined]
    f.available = True  # type: ignore[attr-defined]
    return f


def is_blind(holdout_fn: ScoreFn, child: HullState, parent: HullState, rtol: float = 1e-9) -> bool:
    """True when ``child`` differs from ``parent`` only in parameters the oracle cannot see."""
    sens = getattr(holdout_fn, "sensitive_to", None)
    if sens is None:
        return False
    changed = [
        k for k in HULL_KEYS
        if not math.isclose(float(getattr(child, k)), float(getattr(parent, k)), rel_tol=rtol, abs_tol=1e-12)
    ]
    return bool(changed) and all(k not in sens for k in changed)


def oracle_independence(seen_fn: ScoreFn, holdout_fn: ScoreFn, parent: HullState) -> dict[str, Any]:
    wm = getattr(seen_fn, "wave_model_for", None)
    seen_wm = wm(parent) if callable(wm) else getattr(seen_fn, "wave_model", None)
    hold_wm = getattr(holdout_fn, "wave_model", None)
    indep = None if seen_wm is None or hold_wm is None else seen_wm != hold_wm
    return {"seen_wave_model": seen_wm, "holdout_wave_model": hold_wm, "independent_of_seen": indep}


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
        blind = is_blind(holdout_fn, d, parent)
        s = float(seen_fn(d, parent))
        h = float("nan") if blind else float(holdout_fn(d, parent))
        rows.append(
            {
                "index": i,
                "seen": s,
                "holdout": h,
                "gap": s - h if math.isfinite(h) else None,
                "confirmed": s > 0 and math.isfinite(h) and h > 0,
                "exploit": s > 0 and math.isfinite(h) and h < -exploit_tol,
                "blind": blind,
                "hull": d.to_dict(),
            }
        )
    seen = [r["seen"] for r in rows]
    hold = [r["holdout"] for r in rows]
    finite = [r for r in rows if math.isfinite(r["holdout"])]
    claimed = [r for r in finite if r["seen"] > 0]
    return {
        "schema": "yard_sea_v0.holdout.v2",
        "holdout_oracle": getattr(holdout_fn, "__name__", "holdout"),
        "seen_oracle": getattr(seen_fn, "__name__", "seen"),
        "holdout_available": bool(getattr(holdout_fn, "available", True)),
        "holdout_unavailable_reason": getattr(holdout_fn, "unavailable_reason", None),
        "holdout_sensitive_to": list(getattr(holdout_fn, "sensitive_to", HULL_KEYS)),
        **oracle_independence(seen_fn, holdout_fn, parent),
        "n": len(rows),
        "n_blind": sum(r["blind"] for r in rows),
        "spearman": spearman(seen, hold),
        "sign_agreement": (
            sum((r["seen"] > 0) == (r["holdout"] > 0) for r in finite) / len(finite) if finite else None
        ),
        "n_claimed": len(claimed),
        "n_confirmed": sum(r["confirmed"] for r in rows),
        "n_exploit": sum(r["exploit"] for r in rows),
        "exploit_rate": (sum(r["exploit"] for r in claimed) / len(claimed)) if claimed else None,
        "rows": rows,
        "notes": (
            "Held-out oracle never enters the reward. It is a second model, not ground truth. "
            "blind rows (only unseen parameters changed) and NaN rows are excluded from agreement stats."
        ),
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
        s = float(seen_fn(st, parent))
        h = float("nan") if is_blind(holdout_fn, st, parent) else float(holdout_fn(st, parent))
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


# Convention, not a validated threshold: flag an episode when the reward oracle's
# cumulative improvement estimate is off from the held-out oracle's by more than
# 10% of parent Ct at any step within the horizon. Chosen to be conservative
# (cheap-oracle improvements here are typically a few %); tune per study.
DEFAULT_DRIFT_THRESHOLD = 0.10


def long_horizon_drift_check(
    states: Sequence[HullState],
    parent: HullState,
    *,
    horizon: int | None = None,
    threshold: float = DEFAULT_DRIFT_THRESHOLD,
    seen_fn: ScoreFn = seen_improvement,
    holdout_fn: ScoreFn | None = None,
    episode_id: str | None = None,
) -> dict[str, Any]:
    """Flag (never penalise) long-rollout drift between the reward oracle and a held-out oracle.

    ``seen`` and ``holdout`` are each the *cumulative* relative Ct improvement
    vs the parent at that step, so ``|seen - holdout|`` is the cumulative
    surrogate-vs-reference error as a fraction of parent Ct. ``horizon`` is the
    number of accepted steps checked (default: all of them, i.e. the full
    episode). ``exceeded`` is True when the max error within the horizon is
    above ``threshold``; None when no step had a finite reference value.
    """
    if threshold <= 0 or not math.isfinite(threshold):
        raise ValueError("threshold must be a positive finite fraction")
    if horizon is not None and horizon < 1:
        raise ValueError("horizon must be >= 1 or None (full episode)")
    window = list(states) if horizon is None else list(states)[:horizon]
    dr = trajectory_drift(window, parent, seen_fn=seen_fn, holdout_fn=holdout_fn)
    errs = [e for e in dr["abs_error"] if math.isfinite(e)]
    first_bad = next(
        (i for i, e in enumerate(dr["abs_error"]) if math.isfinite(e) and e > threshold), None
    )
    return {
        "type": "drift_check",
        "schema": "yard_sea_v0.drift_check.v1",
        "episode_id": episode_id,
        "horizon": len(window),
        "horizon_requested": horizon,
        "n_available": len(states),
        "n_finite": len(errs),
        "threshold": float(threshold),
        "threshold_source": (
            "default_convention_not_validated" if threshold == DEFAULT_DRIFT_THRESHOLD else "user"
        ),
        "metric": "max_abs_cumulative_rel_ct_error",
        "max_error": max(errs) if errs else None,
        "final_error": dr["final_error"],
        "first_exceeding_step": first_bad,
        "exceeded": (max(errs) > threshold) if errs else None,
        "seen_oracle": getattr(seen_fn, "__name__", "seen"),
        "holdout_oracle": getattr(holdout_fn, "__name__", "holdout_multi_froude_michell"),
        "affects_reward": False,
        "notes": (
            "Flag only: recorded in evidence, never fed to the reward or the policy. "
            "Error is measured against a second model, not ground truth; the default "
            "threshold is a convention, not a validated limit."
        ),
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
