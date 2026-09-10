"""45-D Ship-D design search env — true Box(45) actions on the Ship-D vector.

Actions are relative deltas in [-1, 1]^45, scaled by a fraction of the 30k
corpus 1–99% percentile span per dim, then clamped into those bands. Binary
Ship-D bits are rounded to {0,1}.

Each step:
  1. apply delta → clamp
  2. evaluate_constraints (49) — reject (monitor) before L1 if infeasible
  3. project_to_hull (or HP calc_volumes when use_hp_hydro=True)
  4. L0 gate — reject before L1 if exploratory hydrostatics fail
  5. L1 resistance reward + evidence pack

DesignSearchEnv (7-D principal morph) remains unchanged.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from .env import DesignSearchEnv, _HAS_GYM, _reward
from .evidence import build_evidence, write_evidence
from .hull import evaluate_l0
from .resistance_l1 import estimate_resistance
from .shipd import (
    BIT_INDICES,
    LABELS,
    ShipDVector,
    action_scales,
    load_action_bounds,
    load_sample_vectors,
    project_to_hull,
)
from .shipd_surface import (
    DEFAULT_NUM_WL,
    DEFAULT_POINTS_PER_WL,
    calc_volumes,
    evaluate_constraints,
    hull_from_volumes,
)

try:
    from gymnasium import spaces
except ImportError:  # pragma: no cover
    spaces = None  # type: ignore

ACTION_DIM = 45


def apply_shipd_delta(
    values: np.ndarray,
    action: np.ndarray,
    *,
    lo: np.ndarray,
    hi: np.ndarray,
    scales: np.ndarray,
) -> np.ndarray:
    """Apply bounded relative deltas; clamp to dataset bands; snap bits."""
    a = np.clip(np.asarray(action, dtype=np.float64).reshape(-1), -1.0, 1.0)
    if a.size != ACTION_DIM:
        raise ValueError(f"expected action length {ACTION_DIM}, got {a.size}")
    out = np.asarray(values, dtype=np.float64).copy()
    out = out + a * scales
    out = np.minimum(np.maximum(out, lo), hi)
    for i in BIT_INDICES:
        out[i] = 1.0 if out[i] >= 0.5 else 0.0
    return out


def hull_from_shipd(
    vec: ShipDVector | np.ndarray | list[float],
    *,
    use_hp_hydro: bool = False,
    volumes_report=None,
    **hydro_kwargs,
):
    """Project Ship-D → HullState; optionally refine Cb/LCB via HP calc_volumes."""
    if use_hp_hydro:
        return hull_from_volumes(vec, report=volumes_report, **hydro_kwargs)
    return project_to_hull(vec)


class DesignSearchEnv45(DesignSearchEnv):
    """Design search with Gymnasium Box(45) actions on the Ship-D vector."""

    metadata = {"render_modes": []}

    def __init__(
        self,
        sample_index: int = 0,
        max_steps: int = 50,
        seed: int = 0,
        evidence_dir: str | None = None,
        delta_frac: float = 0.05,
        use_hp_hydro: bool = False,
        hp_hydro_every_n: int = 0,
        hp_num_wl: int = DEFAULT_NUM_WL,
        hp_points_per_wl: int = DEFAULT_POINTS_PER_WL,
        **kwargs: Any,
    ) -> None:
        samples = load_sample_vectors()
        if sample_index < 0 or sample_index >= len(samples):
            raise IndexError(
                f"sample_index {sample_index} out of range 0..{len(samples) - 1}"
            )
        self.sample_index = int(sample_index)
        self._seed_vector = samples[sample_index]
        self.shipd_vector = self._seed_vector
        self.delta_frac = float(delta_frac)
        # HP Calc_Volumes: default off. When on, run on reset/info; every N
        # accepted steps if hp_hydro_every_n > 0 (0 = reset only).
        self.use_hp_hydro = bool(use_hp_hydro)
        self.hp_hydro_every_n = int(hp_hydro_every_n)
        self.hp_num_wl = int(hp_num_wl)
        self.hp_points_per_wl = int(hp_points_per_wl)
        self._volumes_report = None
        self._lo, self._hi = load_action_bounds()
        self._scales = action_scales(self._lo, self._hi, delta_frac=self.delta_frac)
        self._constraint_report = evaluate_constraints(self.shipd_vector)
        if self.use_hp_hydro:
            self._volumes_report = calc_volumes(
                self.shipd_vector,
                num_wl=self.hp_num_wl,
                points_per_wl=self.hp_points_per_wl,
            )
        parent = hull_from_shipd(
            self.shipd_vector,
            use_hp_hydro=self.use_hp_hydro,
            volumes_report=self._volumes_report,
        )
        # Parent 7-D env for shared obs/evidence plumbing; action_space overridden.
        super().__init__(
            parent=parent,
            max_steps=max_steps,
            seed=seed,
            evidence_dir=evidence_dir,
            **kwargs,
        )
        if _HAS_GYM and spaces is not None:
            self.action_space = spaces.Box(
                low=-1.0, high=1.0, shape=(ACTION_DIM,), dtype=np.float32
            )

    def reset(self, *, seed: int | None = None, options: dict | None = None):
        if options and "shipd_vector" in options:
            self.shipd_vector = (
                options["shipd_vector"]
                if isinstance(options["shipd_vector"], ShipDVector)
                else ShipDVector.from_sequence(options["shipd_vector"])
            )
            self._seed_vector = self.shipd_vector
        else:
            self.shipd_vector = self._seed_vector
        self._constraint_report = evaluate_constraints(self.shipd_vector)
        if self.use_hp_hydro:
            self._volumes_report = calc_volumes(
                self.shipd_vector,
                num_wl=self.hp_num_wl,
                points_per_wl=self.hp_points_per_wl,
            )
        else:
            self._volumes_report = None
        self.parent = hull_from_shipd(
            self.shipd_vector,
            use_hp_hydro=self.use_hp_hydro,
            volumes_report=self._volumes_report,
        )
        if options is None:
            options = {}
        options = {**options, "parent": self.parent}
        obs, info = super().reset(seed=seed, options=options)
        info["shipd_labels"] = LABELS
        info["shipd_vector"] = list(self.shipd_vector.values)
        info["shipd_principal"] = self.shipd_vector.principal()
        info["shipd_constraints"] = self._constraint_report.to_dict()
        info["shipd_feasible"] = self._constraint_report.feasible
        info["action_dim"] = ACTION_DIM
        info["use_hp_hydro"] = self.use_hp_hydro
        if self._volumes_report is not None:
            info["hp_hydro"] = self._volumes_report.to_dict()
        return obs, info

    def step(self, action):
        action_arr = np.asarray(action, dtype=np.float64).reshape(-1)
        if action_arr.size != ACTION_DIM:
            raise ValueError(f"expected action length {ACTION_DIM}, got {action_arr.size}")
        action_list = [float(x) for x in action_arr]

        self.step_count += 1
        terminated = False
        truncated = self.step_count >= self.max_steps

        cur = np.asarray(self.shipd_vector.values, dtype=np.float64)
        proposed = apply_shipd_delta(
            cur, action_arr, lo=self._lo, hi=self._hi, scales=self._scales
        )
        report = evaluate_constraints(proposed)

        if not report.feasible:
            reward = -1.0
            pack = build_evidence(
                hull=self.state,
                l0=evaluate_l0(self.state),
                resistance=None,
                seed=self._seed,
                step=self.step_count,
                episode_id=self.episode_id,
                reward=reward,
                action=action_list,
                monitor_allowed=False,
                monitor_reasons=["shipd_algebraic_constraints"],
            )
            self.evidence_packs.append(pack)
            if self.evidence_dir:
                from pathlib import Path

                write_evidence(pack, Path(self.evidence_dir))
            info = {
                "rejected": True,
                "shipd_infeasible": True,
                "shipd_constraints": report.to_dict(),
                "shipd_vector": list(self.shipd_vector.values),
                "monitor": {
                    "allow": False,
                    "reason_codes": ["shipd_algebraic_constraints"],
                    "projected": None,
                },
            }
            return self._obs(), reward, terminated, truncated, info

        candidate_vec = ShipDVector(tuple(float(x) for x in proposed))
        # Cheap projection for L0 unless this step is an HP hydro refresh tick.
        refresh_hp = (
            self.use_hp_hydro
            and self.hp_hydro_every_n > 0
            and (self.step_count % self.hp_hydro_every_n == 0)
        )
        if refresh_hp:
            step_vol = calc_volumes(
                candidate_vec,
                num_wl=self.hp_num_wl,
                points_per_wl=self.hp_points_per_wl,
            )
            projected = hull_from_shipd(
                candidate_vec, use_hp_hydro=True, volumes_report=step_vol
            )
            self._volumes_report = step_vol
        else:
            projected = hull_from_shipd(candidate_vec, use_hp_hydro=False)
        l0 = evaluate_l0(projected)
        if not l0.feasible:
            reward = -1.0
            pack = build_evidence(
                hull=projected,
                l0=l0,
                resistance=None,
                seed=self._seed,
                step=self.step_count,
                episode_id=self.episode_id,
                reward=reward,
                action=action_list,
                monitor_allowed=False,
                monitor_reasons=l0.violations,
            )
            self.evidence_packs.append(pack)
            if self.evidence_dir:
                from pathlib import Path

                write_evidence(pack, Path(self.evidence_dir))
            info = {
                "rejected": True,
                "shipd_infeasible": False,
                "shipd_constraints": report.to_dict(),
                "shipd_vector": list(candidate_vec.values),
                "l0": l0.to_dict(),
                "monitor": {
                    "allow": False,
                    "reason_codes": list(l0.violations),
                    "projected": projected.to_dict(),
                },
            }
            return self._obs(), reward, terminated, truncated, info

        # Accept: commit Ship-D vector + hull, run L1
        self.shipd_vector = candidate_vec
        self._constraint_report = report
        self.state = projected
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
            action=action_list,
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
            "rejected": False,
            "shipd_infeasible": False,
            "shipd_constraints": report.to_dict(),
            "shipd_vector": list(self.shipd_vector.values),
            "use_hp_hydro": self.use_hp_hydro,
            "monitor": {
                "allow": True,
                "reason_codes": [],
                "projected": self.state.to_dict(),
            },
        }
        if refresh_hp and self._volumes_report is not None:
            info["hp_hydro"] = self._volumes_report.to_dict()
        return self._obs(), reward, terminated, truncated, info
