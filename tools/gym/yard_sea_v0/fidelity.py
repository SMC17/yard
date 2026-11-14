"""Fidelity choice as an agent action, with explicit cost and LF-mistrust fallback to HF.

``FidelityChoiceEnv`` extends ``DesignSearchEnv`` with one extra action
dimension: besides the 7-D hull morph, the agent picks which oracle scores the
step. Every evaluation is charged its cost against an explicit episode budget,
and the reward pays for it, so "always use the expensive model" and "never
check the cheap one" are both visible, priced strategies rather than defaults
baked into the harness.

The agent does not get the last word on the cheap oracle. A ``MistrustMonitor``
keeps paired (LF, HF) measurements and, when the agent asks for LF where LF is
not trusted, evaluates HF as well, charges for it, uses the HF value, and
records why:

* ``cold_start``         — fewer than ``min_pairs`` paired samples so far
* ``lf_hf_error``        — recent mean |LF - HF| above ``max_abs_err``
* ``sign_disagreement``  — LF and HF disagree on improve/worsen too often
* ``extrapolation``      — LF claims more improvement than anything calibrated
* ``audit``              — periodic spot check every ``audit_every`` LF steps

When the agent picks HF, LF is also run (and charged) so the pair can
calibrate the monitor. ``claim_done`` re-measures the final design at HF, so
"done" is never accepted on the cheap oracle's word.

Default ladder (both always available in-repo):

* ``L1``   — Ct improvement at design Fn (Zig HM1984 or Python fallback), cost 1
* ``L1.5`` — multi-Froude score with Michell thin-ship wave term, cost 10

The costs are relative units, not measured seconds; the measured wall time of
every evaluation is recorded beside them. Callers can pass their own ladder
(e.g. L2 Capytaine or L3 OpenFOAM evaluators). The HF level is another model,
not ground truth. Exploratory; not ITTC / not class.
"""

from __future__ import annotations

import math
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Sequence

import numpy as np

from .acceptance import accept_l1
from .env import DesignSearchEnv, _HAS_GYM, _shape_terms
from .evidence import write_evidence
from .hull import HullState
from .multi_froude import multi_froude_score
from .resistance_l1 import estimate_resistance

if _HAS_GYM:
    from gymnasium import spaces

# (child, parent) -> relative improvement (positive = better), or None if not credited.
Evaluator = Callable[[HullState, HullState], "float | None"]


@dataclass(frozen=True)
class FidelityLevel:
    name: str
    cost: float
    evaluate: Evaluator
    description: str = ""


def l1_improvement(child: HullState, parent: HullState) -> float | None:
    rc = estimate_resistance(child)
    if not accept_l1(rc).passed:
        return None
    pc = estimate_resistance(parent).Ct
    return float((pc - rc.Ct) / max(pc, 1e-12))


def michell_multi_froude_improvement(child: HullState, parent: HullState) -> float | None:
    out = multi_froude_score(child, parent, wave_oracle="michell", worst_case_weight=1.0)
    if not out["accepted"] or out["score"] is None:
        return None
    return float(out["score"])


def default_ladder() -> list[FidelityLevel]:
    return [
        FidelityLevel("L1", 1.0, l1_improvement, "L1 Ct at design Fn"),
        FidelityLevel(
            "L1.5", 10.0, michell_multi_froude_improvement,
            "multi-Froude (0.85/1.0/1.25 Fn) with Michell wave, worst-case penalty",
        ),
    ]


@dataclass
class MistrustMonitor:
    """Decides when the low-fidelity number cannot be used on its own."""

    min_pairs: int = 3
    window: int = 8
    max_abs_err: float = 0.02
    max_sign_disagreement: float = 0.25
    extrapolation_margin: float = 0.25
    audit_every: int = 0
    pairs: list[tuple[float, float]] = field(default_factory=list)
    lf_steps: int = 0

    def add_pair(self, lf: float | None, hf: float | None) -> None:
        if lf is None or hf is None or not (math.isfinite(lf) and math.isfinite(hf)):
            return
        self.pairs.append((float(lf), float(hf)))

    def _recent(self) -> list[tuple[float, float]]:
        return self.pairs[-self.window:]

    def stats(self) -> dict[str, Any]:
        rec = self._recent()
        if not rec:
            return {"n_pairs": len(self.pairs), "mean_abs_err": None, "sign_disagreement": None}
        errs = [abs(a - b) for a, b in rec]
        dis = [(a > 0) != (b > 0) for a, b in rec]
        return {
            "n_pairs": len(self.pairs),
            "mean_abs_err": float(np.mean(errs)),
            "sign_disagreement": float(np.mean(dis)),
            "max_lf_calibrated": max(a for a, _ in rec),
        }

    def mistrust(self, lf: float | None) -> str | None:
        """Return a reason string if LF must be backed by HF, else None."""
        self.lf_steps += 1
        if lf is None:
            return "lf_not_credited"
        if len(self.pairs) < self.min_pairs:
            return "cold_start"
        st = self.stats()
        if st["mean_abs_err"] is not None and st["mean_abs_err"] > self.max_abs_err:
            return "lf_hf_error"
        if st["sign_disagreement"] is not None and st["sign_disagreement"] > self.max_sign_disagreement:
            return "sign_disagreement"
        hi = st.get("max_lf_calibrated")
        if hi is not None and lf > hi + self.extrapolation_margin * abs(hi) + 1e-4:
            return "extrapolation"
        if self.audit_every and self.lf_steps % self.audit_every == 0:
            return "audit"
        return None


class FidelityChoiceEnv(DesignSearchEnv):
    """DesignSearchEnv whose 8th action dimension chooses the scoring fidelity.

    Action: Box(8) in [-1, 1]. ``a[:7]`` is the hull morph; ``a[7]`` is binned
    uniformly over ``ladder`` (lowest cost first). Observation: the base 11-D
    observation + ``[cost_spent / cost_budget, lf_trusted]``.

    Reward on an accepted step: ``2 * improvement_used + shape_terms -
    cost_weight * cost_charged / max_cost``. Rejected or uncredited steps earn
    ``-1`` minus the cost actually charged. Episodes truncate at ``max_steps``
    or when ``cost_spent >= cost_budget``.
    """

    def __init__(
        self,
        *args: Any,
        ladder: Sequence[FidelityLevel] | None = None,
        cost_budget: float = 200.0,
        cost_weight: float = 0.05,
        monitor: MistrustMonitor | None = None,
        **kwargs: Any,
    ) -> None:
        kwargs.setdefault("reward_mode", "single_fn")
        super().__init__(*args, **kwargs)
        self.ladder = sorted(list(ladder or default_ladder()), key=lambda lv: lv.cost)
        if len(self.ladder) < 2:
            raise ValueError("ladder needs at least an LF and an HF level")
        self.cost_budget = float(cost_budget)
        self.cost_weight = float(cost_weight)
        self._monitor_template = monitor
        self.monitor = monitor or MistrustMonitor()
        self.cost_spent = 0.0
        self.fidelity_log: list[dict[str, Any]] = []
        if _HAS_GYM:
            self.action_space = spaces.Box(low=-1.0, high=1.0, shape=(8,), dtype=np.float32)
            self.observation_space = spaces.Box(low=-np.inf, high=np.inf, shape=(13,), dtype=np.float32)

    # -------------------------------------------------------------- helpers
    @property
    def lf(self) -> FidelityLevel:
        return self.ladder[0]

    @property
    def hf(self) -> FidelityLevel:
        return self.ladder[-1]

    def level_for(self, selector: float) -> FidelityLevel:
        x = (float(np.clip(selector, -1.0, 1.0)) + 1.0) / 2.0
        idx = min(int(x * len(self.ladder)), len(self.ladder) - 1)
        return self.ladder[idx]

    def _eval(self, level: FidelityLevel, child: HullState) -> tuple[float | None, dict[str, Any]]:
        t0 = time.perf_counter()
        val = level.evaluate(child, self.parent)
        dt = time.perf_counter() - t0
        self.cost_spent += level.cost
        return val, {"level": level.name, "cost": level.cost, "value": val, "wall_s": round(dt, 6)}

    def _obs(self) -> np.ndarray:  # type: ignore[override]
        base = super()._obs()
        trusted = 0.0
        if hasattr(self, "monitor"):
            st = self.monitor.stats()
            trusted = float(
                st["n_pairs"] >= self.monitor.min_pairs
                and st["mean_abs_err"] is not None
                and st["mean_abs_err"] <= self.monitor.max_abs_err
            )
        frac = getattr(self, "cost_spent", 0.0) / max(getattr(self, "cost_budget", 1.0), 1e-9)
        return np.concatenate([base, np.asarray([frac, trusted], dtype=np.float32)])

    # -------------------------------------------------------------- gym API
    def reset(self, *, seed: int | None = None, options: dict | None = None):
        self.cost_spent = 0.0
        self.fidelity_log = []
        self.monitor = (
            MistrustMonitor(**{k: getattr(self._monitor_template, k) for k in (
                "min_pairs", "window", "max_abs_err", "max_sign_disagreement",
                "extrapolation_margin", "audit_every",
            )})
            if self._monitor_template is not None
            else MistrustMonitor()
        )
        obs, info = super().reset(seed=seed, options=options)
        info["fidelity_ladder"] = [{"name": lv.name, "cost": lv.cost} for lv in self.ladder]
        info["cost_budget"] = self.cost_budget
        return obs, info

    def step(self, action):
        a = np.asarray(action, dtype=float).reshape(-1)
        if a.shape[0] != 8:
            raise ValueError("FidelityChoiceEnv expects an 8-D action (7 morph + 1 fidelity)")
        requested = self.level_for(a[7])
        # Run the base step for monitors, L0, L1 acceptance and the evidence pack,
        # but write the pack ourselves once fidelity information is attached.
        ev_dir, self.evidence_dir = self.evidence_dir, None
        try:
            obs, base_reward, terminated, truncated, info = super().step(a[:7])
        finally:
            self.evidence_dir = ev_dir

        evals: list[dict[str, Any]] = []
        record: dict[str, Any] = {
            "step": self.step_count,
            "requested": requested.name,
            "used": None,
            "forced_hf": None,
            "evals": evals,
        }
        max_cost = self.hf.cost
        if info.get("rejected") or not info.get("acceptance", {}).get("passed", False):
            # L0 / L1 envelope rejection: the monitor spends L1 only (already in the base step).
            self.cost_spent += self.lf.cost
            evals.append({"level": "monitor+L1", "cost": self.lf.cost, "value": None, "wall_s": None})
            reward = -1.0 - self.cost_weight * self.lf.cost / max_cost
            record["used"] = None
        else:
            child = self.state
            if requested is self.hf:
                hf_val, e_hf = self._eval(self.hf, child)
                lf_val, e_lf = self._eval(self.lf, child)  # calibration pair, charged
                evals += [e_hf, e_lf]
                self.monitor.add_pair(lf_val, hf_val)
                used_val, record["used"] = hf_val, self.hf.name
            else:
                val, e_req = self._eval(requested, child)
                evals.append(e_req)
                reason = self.monitor.mistrust(val) if requested is self.lf else None
                if reason is not None:
                    hf_val, e_hf = self._eval(self.hf, child)
                    evals.append(e_hf)
                    self.monitor.add_pair(val, hf_val)
                    used_val, record["used"], record["forced_hf"] = hf_val, self.hf.name, reason
                else:
                    used_val, record["used"] = val, requested.name
            charged = sum(e["cost"] for e in evals)
            if used_val is None:
                reward = -1.0 - self.cost_weight * charged / max_cost
            else:
                reward = (
                    2.0 * used_val
                    + _shape_terms(child, self.parent_vol)
                    - self.cost_weight * charged / max_cost
                )
            record["value_used"] = used_val
        record["cost_charged"] = sum(e["cost"] for e in evals)
        record["cost_spent"] = self.cost_spent
        record["monitor"] = self.monitor.stats()
        self.fidelity_log.append(record)

        if self.evidence_packs:
            pack = self.evidence_packs[-1]
            pack["fidelity_choice"] = record
            pack["reward"] = reward
            if self.evidence_dir:
                write_evidence(pack, Path(self.evidence_dir))
        if self.cost_spent >= self.cost_budget:
            truncated = True
        info["fidelity_choice"] = record
        info["base_l1_reward"] = base_reward
        return self._obs(), float(reward), terminated, truncated, info

    def claim_done(self, claimed: dict[str, float] | None = None, **kwargs: Any) -> dict[str, Any]:
        """Base measure-then-claim, plus a fresh HF measurement that must also show improvement."""
        require = kwargs.get("require_improvement", True)
        verdict = super().claim_done(claimed, **kwargs)
        fresh = HullState(**{**HullState.from_vector(self.state.as_vector()).__dict__, **self.state.appendages()})
        hf_val, e_hf = self._eval(self.hf, fresh)
        verdict["hf_measured"] = e_hf
        verdict["cost_spent"] = self.cost_spent
        verdict["fidelity_summary"] = self.summary()
        if hf_val is None:
            verdict["reasons"].append(f"hf_not_credited:{self.hf.name}")
        elif require and hf_val <= 0:
            verdict["reasons"].append(f"no_improvement_at_hf:{self.hf.name}")
        verdict["accepted"] = not verdict["reasons"]
        return verdict

    def summary(self) -> dict[str, Any]:
        log = self.fidelity_log
        forced = [r for r in log if r.get("forced_hf")]
        reasons: dict[str, int] = {}
        for r in forced:
            reasons[r["forced_hf"]] = reasons.get(r["forced_hf"], 0) + 1
        return {
            "n_steps": len(log),
            "requested": {lv.name: sum(r["requested"] == lv.name for r in log) for lv in self.ladder},
            "used": {lv.name: sum(r["used"] == lv.name for r in log) for lv in self.ladder},
            "n_forced_hf": len(forced),
            "forced_reasons": reasons,
            "cost_spent": self.cost_spent,
            "cost_budget": self.cost_budget,
            "monitor": self.monitor.stats(),
        }
