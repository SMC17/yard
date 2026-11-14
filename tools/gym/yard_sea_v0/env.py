"""DesignSearchEnv — Gymnasium-compatible long-horizon hull design search."""

from __future__ import annotations

from typing import Any

import numpy as np

from .acceptance import accept_l1
from .evidence import build_evidence, write_evidence
from .hull import HullState, evaluate_l0
from .monitors import apply_action, monitor_action
from .multi_froude import multi_froude_score

# "sea_state": calm L1 Rt + fast STAwave-2 mean added resistance in a head sea
# (added_resistance.py); Capytaine stays a search-time / held-out cross-check.
REWARD_MODES = ("single_fn", "multi_froude", "sea_state")
from .provenance import (
    OptimizerRecord,
    deterministic_episode_id,
    export_episode_log,
    seeds_record,
)
from .resistance_l1 import estimate_resistance
from .stability_bridge import stability_bonus

try:
    import gymnasium as gym
    from gymnasium import spaces

    _HAS_GYM = True
except ImportError:  # pragma: no cover
    gym = None  # type: ignore
    spaces = None  # type: ignore
    _HAS_GYM = False


def _shape_terms(h: HullState, parent_vol: float) -> float:
    vol_term = (h.volume() - parent_vol) / max(parent_vol, 1e-6)
    gm_term = min(0.5, max(0.0, h.gm0() - 0.15)) * 0.1
    return float(0.5 * vol_term + gm_term + 0.25 * stability_bonus(h))


def _reward(h: HullState, parent_ct: float, parent_vol: float) -> float:
    r = estimate_resistance(h)
    # Improve Ct vs parent; preserve volume
    ct_term = (parent_ct - r.Ct) / max(parent_ct, 1e-6)
    vol_term = (h.volume() - parent_vol) / max(parent_vol, 1e-6)
    gm_term = min(0.5, max(0.0, h.gm0() - 0.15)) * 0.1
    return float(2.0 * ct_term + 0.5 * vol_term + gm_term + 0.25 * stability_bonus(h))


class DesignSearchEnv(gym.Env if _HAS_GYM else object):  # type: ignore[misc]
    """Multi-step parametric hull morph under L0 monitors + L1 resistance reward."""

    metadata = {"render_modes": []}

    def __init__(
        self,
        parent: HullState | None = None,
        max_steps: int = 50,
        seed: int = 0,
        evidence_dir: str | None = None,
        optimizer: OptimizerRecord | None = None,
        reward_mode: str = "single_fn",
        fn_grid: tuple[float, ...] | None = None,
        wave_oracle: str = "auto",
        worst_case_weight: float = 1.0,
        sea_conditions: Any = None,
    ) -> None:
        self.sea_conditions = sea_conditions
        if reward_mode not in REWARD_MODES:
            raise ValueError(f"reward_mode must be one of {REWARD_MODES}")
        self.reward_mode = reward_mode
        self.fn_grid = fn_grid
        self.wave_oracle = wave_oracle
        self.worst_case_weight = worst_case_weight
        self.max_steps = max_steps
        self._seed = seed
        self.base_seed = int(seed)
        self.episode_index = -1
        self.seeds: dict[str, Any] = seeds_record(self.base_seed, 0)
        self.optimizer = optimizer or OptimizerRecord(implementation="unspecified")
        self.evidence_dir = evidence_dir
        self.parent = parent or HullState()
        self.episode_id = ""
        self.state = self.parent
        self.step_count = 0
        self.parent_ct = estimate_resistance(self.parent).Ct
        self.parent_vol = self.parent.volume()
        self.evidence_packs: list[dict[str, Any]] = []
        self.last_claim: dict[str, Any] | None = None
        self.np_random = np.random.default_rng(seed)
        if _HAS_GYM:
            self.action_space = spaces.Box(low=-1.0, high=1.0, shape=(7,), dtype=np.float32)
            # obs: hull vector (7) + [ct, gm0, vol_norm, step_frac]
            self.observation_space = spaces.Box(
                low=-np.inf, high=np.inf, shape=(11,), dtype=np.float32
            )

    def _obs(self) -> np.ndarray:
        r = estimate_resistance(self.state)
        vec = self.state.as_vector() + [
            r.Ct,
            self.state.gm0(),
            self.state.volume() / max(self.parent_vol, 1.0),
            self.step_count / max(self.max_steps, 1),
        ]
        return np.asarray(vec, dtype=np.float32)

    def reset(self, *, seed: int | None = None, options: dict | None = None):
        # Seeded resets with shared randomness: the episode RNG is derived from
        # (base_seed, episode_index) so any two policies replayed with the same
        # pair see identical environment draws (common random numbers).
        if seed is not None:
            self.base_seed = int(seed)
            self.episode_index = -1
        options = options or {}
        if "parent" in options:
            self.parent = options["parent"]
        if "optimizer" in options:
            self.optimizer = options["optimizer"]
        self.episode_index = int(options.get("episode_index", self.episode_index + 1))
        self.seeds = seeds_record(self.base_seed, self.episode_index)
        self._seed = self.seeds["episode_seed"]
        self.np_random = np.random.default_rng(self._seed)
        self.episode_id = deterministic_episode_id(
            self.base_seed, self.episode_index, self.parent.as_vector()
        )
        self.state = HullState(**{k: getattr(self.parent, k) for k in (
            "L", "B", "T", "Cb", "lcb_frac", "kg_frac", "Fn"
        )})
        self.step_count = 0
        self.parent_ct = estimate_resistance(self.parent).Ct
        self.parent_vol = self.parent.volume()
        self.evidence_packs = []
        self.last_claim = None
        obs = self._obs()
        info = {"episode_id": self.episode_id, "parent_ct": self.parent_ct, "seeds": dict(self.seeds)}
        return obs, info

    def step(self, action):
        action = list(np.asarray(action, dtype=float).reshape(-1))
        self.optimizer.tick()
        decision = monitor_action(self.state, action)
        self.step_count += 1
        terminated = False
        truncated = self.step_count >= self.max_steps

        if not decision.allow or decision.projected is None:
            reward = -1.0
            l0 = evaluate_l0(decision.projected or apply_action(self.state, action))
            pack = build_evidence(
                hull=decision.projected or self.state,
                l0=l0,
                resistance=None,
                seed=self._seed,
                step=self.step_count,
                episode_id=self.episode_id,
                reward=reward,
                action=action,
                monitor_allowed=False,
                monitor_reasons=decision.reason_codes,
                parent_id=None,
                optimizer=self.optimizer.to_dict(),
                seeds=dict(self.seeds),
            )
            self.evidence_packs.append(pack)
            if self.evidence_dir:
                from pathlib import Path

                write_evidence(pack, Path(self.evidence_dir))
            info = {"monitor": decision.to_dict(), "rejected": True}
            return self._obs(), reward, terminated, truncated, info

        self.state = decision.projected
        l0 = evaluate_l0(self.state)
        res = estimate_resistance(self.state)
        acc = accept_l1(res, hull=self.state).to_dict()
        mf = None
        if self.reward_mode == "multi_froude":
            mf = multi_froude_score(
                self.state,
                self.parent,
                self.fn_grid,
                wave_oracle=self.wave_oracle,
                worst_case_weight=self.worst_case_weight,
            )
            ok = acc["passed"] and mf["accepted"]
            reward = (2.0 * mf["score"] + _shape_terms(self.state, self.parent_vol)) if ok else -1.0
        elif self.reward_mode == "sea_state":
            mf = self._sea_score(self.state)
            ok = acc["passed"] and mf["accepted"]
            reward = (2.0 * mf["score"] + _shape_terms(self.state, self.parent_vol)) if ok else -1.0
        else:
            # Acceptance gate: an L1 number whose envelope checks fail earns no credit.
            reward = _reward(self.state, self.parent_ct, self.parent_vol) if acc["passed"] else -1.0
        pack = build_evidence(
            hull=self.state,
            l0=l0,
            resistance=res,
            seed=self._seed,
            step=self.step_count,
            episode_id=self.episode_id,
            reward=reward,
            action=action,
            monitor_allowed=True,
            monitor_reasons=[],
            acceptance=acc,
            optimizer=self.optimizer.to_dict(),
            seeds=dict(self.seeds),
        )
        if mf is not None:
            pack["sea_state" if self.reward_mode == "sea_state" else "multi_froude"] = mf
        self.evidence_packs.append(pack)
        if self.evidence_dir:
            from pathlib import Path

            write_evidence(pack, Path(self.evidence_dir))
        info = {
            "multi_froude": mf,
            "ct": res.Ct,
            "gm0": self.state.gm0(),
            "Rt_N": res.Rt_N,
            "l1_fidelity": res.fidelity,
            "monitor": decision.to_dict(),
            "rejected": False,
            "acceptance": acc,
        }
        return self._obs(), reward, terminated, truncated, info

    def _sea_score(self, h: HullState) -> dict[str, Any]:
        from .added_resistance import DEFAULT_SEA_CONDITIONS, sea_state_score

        return sea_state_score(h, self.parent, self.sea_conditions or DEFAULT_SEA_CONDITIONS,
                               worst_case_weight=self.worst_case_weight)

    def candidate_reward(self, h: HullState) -> float:
        """Reward ``step`` would assign to an already-monitored hull (for look-ahead search)."""
        acc = accept_l1(estimate_resistance(h))
        if self.reward_mode == "sea_state":
            ss = self._sea_score(h)
            if not (acc.passed and ss["accepted"]):
                return -1.0
            return 2.0 * ss["score"] + _shape_terms(h, self.parent_vol)
        if self.reward_mode == "multi_froude":
            mf = multi_froude_score(
                h, self.parent, self.fn_grid,
                wave_oracle=self.wave_oracle, worst_case_weight=self.worst_case_weight,
            )
            if not (acc.passed and mf["accepted"]):
                return -1.0
            return 2.0 * mf["score"] + _shape_terms(h, self.parent_vol)
        return _reward(h, self.parent_ct, self.parent_vol) if acc.passed else -1.0

    # ------------------------------------------------------------ measure-then-claim
    def claim_done(
        self,
        claimed: dict[str, float] | None = None,
        *,
        rel_tol: float = 1e-6,
        require_improvement: bool = True,
    ) -> dict[str, Any]:
        """Accept an agent's "done" only after re-measuring the final geometry.

        The final hull is rebuilt from its parameter vector (no cached objects),
        L0 and the L1 oracle are re-run, and the L1 acceptance gate is applied.
        Any values the agent *claims* (``Ct``, ``gm0``, ``volume``) must match
        the fresh measurement within ``rel_tol``. The verdict is appended to
        ``evidence_packs`` as a ``claim`` record and returned.
        """
        fresh = HullState.from_vector(self.state.as_vector())
        l0 = evaluate_l0(fresh)
        res = estimate_resistance(fresh)
        acc = accept_l1(res)
        measured = {"Ct": res.Ct, "gm0": fresh.gm0(), "volume": fresh.volume()}
        reasons: list[str] = []
        if not l0.feasible:
            reasons.append("l0_infeasible:" + ",".join(l0.violations))
        if not acc.passed:
            reasons.append("acceptance_failed:" + ",".join(acc.failed_checks))
        mismatches = {}
        for k, v in (claimed or {}).items():
            if k not in measured:
                reasons.append(f"unmeasurable_claim:{k}")
                continue
            m = measured[k]
            if abs(float(v) - m) > rel_tol * max(abs(m), 1e-12):
                mismatches[k] = {"claimed": float(v), "measured": m}
        if mismatches:
            reasons.append("claim_mismatch:" + ",".join(sorted(mismatches)))
        improved = res.Ct < self.parent_ct
        mf = None
        if self.reward_mode == "multi_froude":
            # Improvement must hold across the Froude grid, not just at design Fn.
            mf = multi_froude_score(
                fresh, self.parent, self.fn_grid,
                wave_oracle=self.wave_oracle, worst_case_weight=self.worst_case_weight,
            )
            improved = bool(mf["accepted"] and mf["score"] is not None and mf["score"] > 0)
            measured["multi_froude_score"] = mf["score"]
        elif self.reward_mode == "sea_state":
            mf = self._sea_score(fresh)
            improved = bool(mf["accepted"] and mf["score"] is not None and mf["score"] > 0)
            measured["sea_state_score"] = mf["score"]
        if require_improvement and not improved:
            reasons.append("no_improvement_vs_parent")
        verdict = {
            "type": "claim",
            "schema": "yard_sea_v0.claim.v1",
            "episode_id": self.episode_id,
            "step": self.step_count,
            "accepted": not reasons,
            "reasons": reasons,
            "measured": measured,
            "claimed": dict(claimed or {}),
            "mismatches": mismatches,
            "parent_ct": self.parent_ct,
            "improved": improved,
            "reward_mode": self.reward_mode,
            "multi_froude": mf,
            "l0": l0.to_dict(),
            "acceptance": acc.to_dict(),
            "hull": fresh.to_dict(),
            "optimizer": self.optimizer.to_dict(),
            "seeds": dict(self.seeds),
            "notes": "Measure-then-claim: verdict from a fresh re-evaluation, not the agent's report.",
        }
        self.evidence_packs.append(verdict)
        self.last_claim = verdict
        return verdict

    def record_evidence(self, record: dict[str, Any]) -> dict[str, Any]:
        """Append a non-step record (e.g. a drift_check flag) to this episode's evidence.

        It never changes state or reward. It is written next to the step packs
        when ``evidence_dir`` is set, and included in ``export_log``.
        """
        rec = dict(record)
        rec.setdefault("episode_id", self.episode_id)
        rec.setdefault("step", self.step_count)
        rec.setdefault("optimizer_implementation", self.optimizer.to_dict().get("implementation"))
        if "evidence_id" not in rec:
            # Deterministic, content-derived id: episodes share episode_id across policies (CRN).
            import json
            import uuid

            body = json.dumps(rec, sort_keys=True, default=str)
            rec["evidence_id"] = f"{rec.get('type', 'record')}-{uuid.uuid5(uuid.NAMESPACE_URL, body)}"
        self.evidence_packs.append(rec)
        if self.evidence_dir:
            from pathlib import Path

            write_evidence(rec, Path(self.evidence_dir))
        return rec

    def export_log(self, path: str) -> dict[str, Any]:
        """Write this episode's evidence + claim records as a digest-chained JSONL log."""
        return export_episode_log(
            self.evidence_packs,
            path,
            header={
                "episode_id": self.episode_id,
                "seeds": dict(self.seeds),
                "optimizer": self.optimizer.to_dict(),
                "parent": self.parent.to_dict(),
                "max_steps": self.max_steps,
            },
        )
