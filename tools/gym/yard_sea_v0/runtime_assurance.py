"""Simplex-style runtime assurance (``rta_simplex_v0``).

Architecture (after the public Simplex pattern: an untrusted *advanced*
controller, a simple trusted *fallback*, and a *decision module* that switches
on a safety monitor): every step the advanced controller proposes an action,
the monitor judges it, and the decision module either passes it through or
substitutes the fallback's action. The fallback runs every step in shadow mode
so its internal state is current when it takes over. Switching back to the
advanced controller needs ``recovery_steps`` consecutive safe proposals
(hysteresis). Every switch is logged and summarised for the evidence pack.

Honest limits: the monitors here are simple predictive checks (straight-line
CPA with an uncertainty margin; L0 hydrostatic feasibility), not verified
reachability analysis; the fallbacks are the repo's rule-based baselines. There
is **no formal safety guarantee**, no certified monitor, and no claim of
conformance to any runtime-assurance standard (e.g. ASTM F3269) — the layout
borrows the vocabulary only.

Provided:

* ``Simplex`` — generic decision module + log.
* ``CpaMonitor`` / ``ColregRTA`` — navigation: wraps any heading policy in the
  COLREG suite (``simulate(..., wrapper=ColregRTA(...))``).
* ``HoldCoursePolicy`` / ``JitterPolicy`` — labelled *stand-ins* for an
  untrusted learned policy (no trained agent ships in this repo).
* ``DesignSimplex`` — design-search: wraps ``DesignSearchEnv``; an action the
  L0 monitor would reject is replaced by the largest feasible scaling of it
  (or a no-op), and the intervention is written to the episode evidence.
* ``FaultyObservation`` — fault-injection hook on env observations for eval.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field, replace
from typing import Any, Callable, Sequence

import numpy as np

from .colreg_stub import Thresholds, Vessel, _wrap360, classify, cpa_tcpa
from .faults import FaultInjector

LABEL = "rta_simplex_v0"
NO_GUARANTEE = (
    "Simplex-style switching with simple predictive monitors and rule-based fallbacks. "
    "No formal guarantee, not a certified monitor, no standard-conformance claim."
)


@dataclass
class Verdict:
    safe: bool
    reasons: list[str] = field(default_factory=list)
    margin: float | None = None


@dataclass
class Simplex:
    """Decision module: pass the advanced action through unless the monitor objects."""

    monitor: Callable[[Any, Any], Verdict]
    recovery_steps: int = 3
    name: str = LABEL
    in_fallback: bool = False
    _safe_streak: int = 0
    steps: int = 0
    fallback_steps: int = 0
    events: list[dict[str, Any]] = field(default_factory=list)

    def decide(self, t: float, ctx: Any, proposed: Any, fallback_action: Any) -> tuple[Any, Verdict]:
        self.steps += 1
        v = self.monitor(ctx, proposed)
        if v.safe:
            self._safe_streak += 1
        else:
            self._safe_streak = 0
        if not self.in_fallback and not v.safe:
            self.in_fallback = True
            self.events.append({"t": t, "switch": "advanced->fallback", "reasons": list(v.reasons),
                                "margin": v.margin})
        elif self.in_fallback and self._safe_streak >= self.recovery_steps:
            self.in_fallback = False
            self.events.append({"t": t, "switch": "fallback->advanced", "reasons": []})
        if self.in_fallback:
            self.fallback_steps += 1
            return fallback_action, v
        return proposed, v

    def summary(self) -> dict[str, Any]:
        return {"label": LABEL, "name": self.name, "steps": self.steps,
                "fallback_steps": self.fallback_steps,
                "fallback_fraction": self.fallback_steps / self.steps if self.steps else 0.0,
                "n_switches_to_fallback": sum(e["switch"] == "advanced->fallback" for e in self.events),
                "events": list(self.events), "recovery_steps": self.recovery_steps,
                "notes": NO_GUARANTEE}


# ---------------------------------------------------------------- navigation
@dataclass
class CpaMonitor:
    """Unsafe if the proposed course gives a perceived CPA below ``dcpa_min + uncertainty``
    within ``horizon_s``, or turns to port while give-way in head-on / starboard crossing.

    ``uncertainty_m`` is a user-set allowance for perception error (e.g. degraded GNSS);
    it is a convention, not an estimate produced by this module.
    """

    th: Thresholds = field(default_factory=Thresholds)
    horizon_s: float = 1200.0
    uncertainty_m: float = 0.0
    port_turn_tol_deg: float = 5.0

    def __call__(self, ctx: tuple[Vessel, list[Vessel], float], course: float) -> Verdict:
        own, targets, route = ctx
        prop = replace(own, course_deg=_wrap360(course))
        reasons: list[str] = []
        margin = math.inf
        need = self.th.dcpa_min_m + self.uncertainty_m
        alt = (course - route + 180.0) % 360.0 - 180.0
        for i, tg in enumerate(targets):
            d, t = cpa_tcpa(prop, tg)
            if 0.0 < t < self.horizon_s:
                margin = min(margin, d - need)
                if d < need:
                    reasons.append(f"t{i}_cpa_{d:.0f}m_lt_{need:.0f}m_in_{t:.0f}s")
            c = classify(own, tg, replace(self.th, tcpa_max_s=self.horizon_s))
            if (c["risk_of_collision"] and c["role"] == "give_way"
                    and c["encounter"] in ("head_on", "crossing_starboard") and alt < -self.port_turn_tol_deg):
                reasons.append(f"t{i}_port_turn_in_{c['encounter']}")
        return Verdict(not reasons, reasons, None if margin == math.inf else margin)


@dataclass
class ColregRTA:
    """Wrapper for ``colreg_suite.simulate``: advanced policy → monitor → baseline fallback."""

    monitor: CpaMonitor = field(default_factory=CpaMonitor)
    fallback: Any = None
    recovery_steps: int = 6

    def __post_init__(self) -> None:
        if self.fallback is None:
            from .colreg_suite import BaselineColregController

            self.fallback = BaselineColregController(th=self.monitor.th)
        self.simplex = Simplex(self.monitor, recovery_steps=self.recovery_steps, name="colreg_rta")

    def filter(self, t: float, own: Vessel, targets: list[Vessel], route: float, proposed: float) -> float:
        fb = self.fallback(t, own, targets, route)  # shadow mode: always running
        out, _ = self.simplex.decide(t, (own, targets, route), proposed, fb)
        return out

    def summary(self) -> dict[str, Any]:
        s = self.simplex.summary()
        s.update({"monitor": {"type": "cpa_straight_line", "horizon_s": self.monitor.horizon_s,
                              "uncertainty_m": self.monitor.uncertainty_m,
                              "dcpa_min_m": self.monitor.th.dcpa_min_m},
                  "fallback": getattr(self.fallback, "name", type(self.fallback).__name__)})
        return s


class HoldCoursePolicy:
    """STAND-IN for an untrusted learned policy: always steers the route (ignores traffic)."""

    name = "standin_hold_course"

    def __call__(self, t: float, own: Vessel, targets: list[Vessel], route: float) -> float:
        return route


@dataclass
class JitterPolicy:
    """STAND-IN for an untrusted learned policy: route ± seeded random heading jitter."""

    amplitude_deg: float = 40.0
    seed: int = 0
    name: str = "standin_jitter"

    def __post_init__(self) -> None:
        self._rng = np.random.default_rng(self.seed)
        self._cur = 0.0

    def __call__(self, t: float, own: Vessel, targets: list[Vessel], route: float) -> float:
        if int(t) % 120 == 0:
            self._cur = float(self._rng.uniform(-self.amplitude_deg, self.amplitude_deg))
        return _wrap360(route + self._cur)


# ---------------------------------------------------------------- design search
class DesignSimplex:
    """Wrap ``DesignSearchEnv``: substitute a feasible fallback for actions the L0 monitor rejects.

    Fallback = the largest ``s ∈ {1/2, 1/4, …}`` with ``s·action`` allowed, else a zero
    (no-op) action. Interventions are written to the env's evidence via ``record_evidence``.
    """

    def __init__(self, env: Any, *, bisections: int = 6, recovery_steps: int = 1) -> None:
        from .monitors import monitor_action

        self.env = env
        self.bisections = bisections
        self._monitor_action = monitor_action
        self.simplex = Simplex(self._monitor, recovery_steps=recovery_steps, name="design_rta")

    def _monitor(self, state: Any, action: Sequence[float]) -> Verdict:
        d = self._monitor_action(state, list(action))
        return Verdict(d.allow, list(d.reason_codes))

    def _fallback(self, action: np.ndarray) -> tuple[np.ndarray, float]:
        s = 1.0
        for _ in range(self.bisections):
            s *= 0.5
            if self._monitor_action(self.env.state, list(action * s)).allow:
                return action * s, s
        return np.zeros_like(action), 0.0

    def reset(self, **kw: Any):
        return self.env.reset(**kw)

    def step(self, action: Sequence[float]):
        a = np.asarray(action, dtype=float).reshape(-1)
        fb, scale = self._fallback(a) if not self._monitor(self.env.state, a).safe else (a, 1.0)
        out, v = self.simplex.decide(self.env.step_count, self.env.state, a, fb)
        obs, reward, term, trunc, info = self.env.step(out)
        info = dict(info)
        info["rta"] = {"substituted": out is not a, "reasons": v.reasons,
                       "fallback_scale": scale if out is not a else None}
        if out is not a:
            self.env.record_evidence({"type": "rta_intervention", "label": LABEL,
                                      "proposed_action": a.tolist(), "executed_action": list(map(float, out)),
                                      "fallback_scale": scale, "reasons": v.reasons, "notes": NO_GUARANTEE})
        return obs, reward, term, trunc, info

    def summary(self) -> dict[str, Any]:
        return self.simplex.summary()


class FaultyObservation:
    """Eval hook: pass env observations through a ``FaultInjector`` on channel ``obs``.

    A dropped sample returns the last delivered observation (stale hold).
    """

    def __init__(self, env: Any, injector: FaultInjector) -> None:
        self.env, self.injector = env, injector
        self._last: np.ndarray | None = None

    def _f(self, obs: np.ndarray) -> np.ndarray:
        o = self.injector.apply("obs", float(self.env.step_count), obs)
        if o is None:
            o = self._last if self._last is not None else np.asarray(obs, dtype=float)
        self._last = np.asarray(o, dtype=float)
        return self._last.astype(np.float32)

    def reset(self, **kw: Any):
        obs, info = self.env.reset(**kw)
        return self._f(obs), info

    def step(self, action: Any):
        obs, r, te, tr, info = self.env.step(action)
        return self._f(obs), r, te, tr, info
