"""Multi-Froude resistance scoring with friction and pressure terms kept separate.

Why: a hull can tie its parent at the design speed and still be much worse a few
knots off design (public KCS optimisation results report a design matching the
baseline at Fn 0.195 yet 45-50% worse at Fn 0.25). Scoring one Fn rewards that
kind of point-optimised hull. Here every candidate is scored on a Froude grid,
and each Fn is decomposed into

* ``friction``          — ITTC-57 flat-plate Cf (L1)
* ``viscous_pressure``  — form-factor part k·Cf (L1)
* ``wave``              — wave-making Cw: L1 Holtrop-style term, or L1.5 Michell
                          thin-ship integral when ``wave_oracle="michell"``
* ``pressure``          — viscous_pressure + wave

with the per-Fn acceptance gate applied (out-of-envelope points are not credited).

Which wave term (measured on the default 120 m, Cb 0.75 hull):

* Zig HM1984 L1 (``hm1984_zig``, default when ``zig_gym`` is built): Cw is
  3% / 22% / 49% of Ct at Fn 0.15 / 0.20 / 0.25 — a real Holtrop-Mennen wave
  term, so off-design penalties show up.
* Python fallback L1 (``simplified_py``): Cw is heavily damped (0.1% / 0.9% /
  2.7%), so the grid is nearly friction-only and cannot express off-design
  wave penalties. It is labelled, not recalibrated: no tuning to make numbers
  look right.
* Michell L1.5 (vendored Ship-D ModMichell, ~10 ms/eval): thin-ship Cw.

``wave_oracle="auto"`` (the default) resolves to ``l1`` when L1 is HM1984,
else ``michell`` when the vendored module is present, else ``l1`` with
``wave_term_damped=True`` on the result. The resolved oracle is recorded.
All are exploratory ranking signals — not ITTC powering, not model-test
validated, not class.
"""

from __future__ import annotations

import dataclasses
import math
from dataclasses import dataclass, field
from typing import Any, Sequence

from .acceptance import accept_l1
from .hull import HullState
from .resistance_l1 import estimate_resistance

DEFAULT_FN_FACTORS: tuple[float, ...] = (0.85, 1.0, 1.25)  # around design Fn
WAVE_ORACLES = ("l1", "michell")
WAVE_ORACLE_CHOICES = ("auto",) + WAVE_ORACLES
DAMPED_L1_FIDELITIES = ("simplified_py",)


def resolve_wave_oracle(requested: str, h: HullState) -> dict[str, Any]:
    """Resolve ``auto`` to a concrete wave oracle and say why.

    Returns ``{"requested", "resolved", "l1_fidelity", "wave_term_damped", "reason"}``.
    """
    if requested not in WAVE_ORACLE_CHOICES:
        raise ValueError(f"wave_oracle must be one of {WAVE_ORACLE_CHOICES}")
    l1_fid = str(estimate_resistance(h).fidelity)
    l1_damped = l1_fid in DAMPED_L1_FIDELITIES
    if requested != "auto":
        resolved, reason = requested, "explicit"
    elif not l1_damped:
        resolved, reason = "l1", f"l1_is_{l1_fid}"
    else:
        from .teachers import michell_l15

        if michell_l15.detect().available:
            resolved, reason = "michell", f"l1_{l1_fid}_wave_term_damped"
        else:
            resolved, reason = "l1", "michell_unavailable"
    return {
        "requested": requested,
        "resolved": resolved,
        "l1_fidelity": l1_fid,
        "wave_term_damped": resolved == "l1" and l1_damped,
        "reason": reason,
    }


def fn_grid_for(h: HullState, factors: Sequence[float] = DEFAULT_FN_FACTORS) -> tuple[float, ...]:
    return tuple(round(h.Fn * f, 6) for f in factors)


@dataclass
class FroudePoint:
    Fn: float
    friction: float
    viscous_pressure: float
    wave: float
    allowance: float
    accepted: bool
    failed_checks: list[str] = field(default_factory=list)
    wave_oracle: str = "l1"

    @property
    def pressure(self) -> float:
        return self.viscous_pressure + self.wave

    @property
    def total(self) -> float:
        return self.friction + self.pressure + self.allowance

    def to_dict(self) -> dict[str, Any]:
        return {
            "Fn": self.Fn,
            "friction": self.friction,
            "viscous_pressure": self.viscous_pressure,
            "wave": self.wave,
            "pressure": self.pressure,
            "allowance": self.allowance,
            "total": self.total,
            "accepted": self.accepted,
            "failed_checks": list(self.failed_checks),
            "wave_oracle": self.wave_oracle,
        }


def _michell_cw(h: HullState) -> tuple[float | None, str | None]:
    from .teachers import michell_l15

    r = michell_l15.run(h)
    cw = r.get("Cw")
    if r.get("skipped") or cw is None or not math.isfinite(float(cw)):
        return None, str(r.get("skip_reason") or "michell_failed")
    return float(cw), None


def evaluate_point(h: HullState, Fn: float, *, wave_oracle: str = "l1") -> FroudePoint:
    if wave_oracle == "auto":
        wave_oracle = resolve_wave_oracle("auto", h)["resolved"]
    if wave_oracle not in WAVE_ORACLES:
        raise ValueError(f"wave_oracle must be one of {WAVE_ORACLES}")
    hf = dataclasses.replace(h, Fn=float(Fn))
    r = estimate_resistance(hf)
    acc = accept_l1(r)
    failed = list(acc.failed_checks)
    wave = float(r.Cw)
    if wave_oracle == "michell":
        cw, why = _michell_cw(hf)
        if cw is None:
            failed.append(f"michell:{why}")
        else:
            wave = cw
    allowance = float(r.Ct - r.Cf * (1.0 + r.k1) - r.Cw)
    return FroudePoint(
        Fn=float(Fn),
        friction=float(r.Cf),
        viscous_pressure=float(r.k1 * r.Cf),
        wave=wave,
        allowance=allowance,
        accepted=not failed,
        failed_checks=failed,
        wave_oracle=wave_oracle,
    )


def evaluate_grid(
    h: HullState, fn_grid: Sequence[float] | None = None, *, wave_oracle: str = "auto"
) -> list[FroudePoint]:
    grid = tuple(fn_grid) if fn_grid else fn_grid_for(h)
    wave_oracle = resolve_wave_oracle(wave_oracle, h)["resolved"]
    return [evaluate_point(h, fn, wave_oracle=wave_oracle) for fn in grid]


def multi_froude_score(
    child: HullState,
    parent: HullState,
    fn_grid: Sequence[float] | None = None,
    *,
    weights: Sequence[float] | None = None,
    worst_case_weight: float = 1.0,
    wave_oracle: str = "auto",
) -> dict[str, Any]:
    """Relative resistance improvement of ``child`` vs ``parent`` on a Froude grid.

    Per Fn: ``d_total = (parent.total - child.total) / parent.total`` and the same
    split into ``d_friction`` and ``d_pressure`` (both normalised by parent total,
    so ``d_friction + d_pressure + d_allowance == d_total``).

    ``score = weighted_mean(d_total) + worst_case_weight * min(0, min(d_total))`` —
    any speed where the child is worse than the parent is penalised on top of the
    average. Points failing acceptance (either hull) are excluded; if none remain
    ``score`` is None and ``accepted`` is False.
    """
    grid = tuple(fn_grid) if fn_grid else fn_grid_for(parent)
    wave = resolve_wave_oracle(wave_oracle, parent)
    wave_oracle = wave["resolved"]
    w = list(weights) if weights is not None else [1.0] * len(grid)
    if len(w) != len(grid):
        raise ValueError("weights must match fn_grid length")
    rows = []
    for fn, wi in zip(grid, w):
        c = evaluate_point(child, fn, wave_oracle=wave_oracle)
        p = evaluate_point(parent, fn, wave_oracle=wave_oracle)
        ok = c.accepted and p.accepted and p.total > 0
        pt = p.total if p.total > 0 else float("nan")
        rows.append(
            {
                "Fn": fn,
                "weight": wi,
                "credited": ok,
                "child": c.to_dict(),
                "parent": p.to_dict(),
                "d_total": (p.total - c.total) / pt,
                "d_friction": (p.friction - c.friction) / pt,
                "d_pressure": (p.pressure - c.pressure) / pt,
                "d_wave": (p.wave - c.wave) / pt,
            }
        )
    credited = [r for r in rows if r["credited"]]
    if not credited:
        return {"accepted": False, "score": None, "fn_grid": list(grid), "points": rows,
                "wave_oracle": wave_oracle, "wave_resolution": wave,
                "reason": "no_point_passed_acceptance"}
    wsum = sum(r["weight"] for r in credited) or 1.0
    mean_total = sum(r["weight"] * r["d_total"] for r in credited) / wsum
    worst = min(r["d_total"] for r in credited)
    worst_fn = min(credited, key=lambda r: r["d_total"])["Fn"]
    score = mean_total + worst_case_weight * min(0.0, worst)
    return {
        "accepted": len(credited) == len(rows),
        "score": score,
        "mean_d_total": mean_total,
        "mean_d_friction": sum(r["weight"] * r["d_friction"] for r in credited) / wsum,
        "mean_d_pressure": sum(r["weight"] * r["d_pressure"] for r in credited) / wsum,
        "worst_d_total": worst,
        "worst_Fn": worst_fn,
        "n_credited": len(credited),
        "fn_grid": list(grid),
        "points": rows,
        "wave_oracle": wave_oracle,
        "wave_resolution": wave,
        "notes": "Exploratory multi-Fn ranking; not ITTC powering / not class.",
    }
