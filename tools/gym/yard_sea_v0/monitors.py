"""Runtime monitors — reject illegal actions before L1 evaluation (F3269-style)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .hull import HullState, evaluate_l0


@dataclass
class MonitorDecision:
    allow: bool
    reason_codes: list[str]
    projected: HullState | None

    def to_dict(self) -> dict[str, Any]:
        return {
            "allow": self.allow,
            "reason_codes": list(self.reason_codes),
            "projected": None if self.projected is None else self.projected.to_dict(),
        }


def apply_action(h: HullState, action: list[float] | tuple[float, ...]) -> HullState:
    """Action: bounded relative deltas for [L,B,T,Cb,lcb_frac,kg_frac,Fn]."""
    scales = [0.05, 0.05, 0.05, 0.03, 0.01, 0.02, 0.02]
    vals = h.as_vector()
    out = []
    for i, a in enumerate(action[:7]):
        a = max(-1.0, min(1.0, float(a)))
        if i in (3, 4, 5, 6):
            out.append(vals[i] + a * scales[i])
        else:
            out.append(vals[i] * (1.0 + a * scales[i]))
    return HullState.from_vector(out).clamp_soft()


def monitor_action(h: HullState, action: list[float] | tuple[float, ...]) -> MonitorDecision:
    projected = apply_action(h, action)
    report = evaluate_l0(projected)
    if not report.feasible:
        return MonitorDecision(
            allow=False,
            reason_codes=report.violations,
            projected=projected,
        )
    return MonitorDecision(allow=True, reason_codes=[], projected=projected)
