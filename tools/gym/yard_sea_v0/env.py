"""DesignSearchEnv — Gymnasium-compatible long-horizon hull design search."""

from __future__ import annotations

import uuid
from typing import Any

import numpy as np

from .evidence import build_evidence, write_evidence
from .hull import HullState, evaluate_l0
from .monitors import apply_action, monitor_action
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
    ) -> None:
        self.max_steps = max_steps
        self._seed = seed
        self.evidence_dir = evidence_dir
        self.parent = parent or HullState()
        self.episode_id = ""
        self.state = self.parent
        self.step_count = 0
        self.parent_ct = estimate_resistance(self.parent).Ct
        self.parent_vol = self.parent.volume()
        self.evidence_packs: list[dict[str, Any]] = []
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
        if seed is not None:
            self._seed = seed
            self.np_random = np.random.default_rng(seed)
        if options and "parent" in options:
            self.parent = options["parent"]
        self.episode_id = str(uuid.uuid4())
        self.state = HullState(**{k: getattr(self.parent, k) for k in (
            "L", "B", "T", "Cb", "lcb_frac", "kg_frac", "Fn"
        )})
        self.step_count = 0
        self.parent_ct = estimate_resistance(self.parent).Ct
        self.parent_vol = self.parent.volume()
        self.evidence_packs = []
        obs = self._obs()
        info = {"episode_id": self.episode_id, "parent_ct": self.parent_ct}
        return obs, info

    def step(self, action):
        action = list(np.asarray(action, dtype=float).reshape(-1))
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
        reward = _reward(self.state, self.parent_ct, self.parent_vol)
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
        )
        self.evidence_packs.append(pack)
        if self.evidence_dir:
            from pathlib import Path

            write_evidence(pack, Path(self.evidence_dir))
        info = {
            "ct": res.Ct,
            "gm0": self.state.gm0(),
            "Rt_N": res.Rt_N,
            "l1_fidelity": res.fidelity,
            "monitor": decision.to_dict(),
            "rejected": False,
        }
        return self._obs(), reward, terminated, truncated, info
