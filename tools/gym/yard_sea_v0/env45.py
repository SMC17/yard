"""45-D Ship-D design search env — true Box(45) actions on the Ship-D vector.

Actions are relative deltas in [-1, 1]^45, scaled by a fraction of the 30k
corpus 1–99% percentile span per dim, then clamped into those bands. Binary
Ship-D bits are rounded to {0,1}.

Each step:
  1. apply delta → clamp
  2. evaluate_constraints (49) — reject (monitor) before L1 if infeasible
  3. HP geometry/hydro primary (calc_volumes) when use_hp_geometry;
     project_to_hull fallback only
  4. L0 gate — reject before L1 if exploratory hydrostatics fail
  5. L1 resistance reward + evidence pack

DesignSearchEnv (7-D principal morph) remains unchanged.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from .env import DesignSearchEnv, _HAS_GYM, _reward
from .evidence import build_evidence, write_evidence
from .hp_rank import GEOMETRY_FALLBACK, GEOMETRY_HP, hp_geometry_default, hull_from_shipd_primary
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
    use_hp_geometry: bool | None = None,
    volumes_report=None,
    **hydro_kwargs,
):
    """Ship-D → HullState.

    Prefer HP calc_volumes when ``use_hp_geometry`` or ``use_hp_hydro`` is True.
    ``project_to_hull`` is fallback only.
    """
    prefer = bool(use_hp_hydro) if use_hp_geometry is None else bool(use_hp_geometry)
    if prefer or use_hp_hydro:
        hull, source, _vol, _reason = hull_from_shipd_primary(
            vec,
            prefer_hp=True,
            volumes_report=volumes_report,
            **{k: v for k, v in hydro_kwargs.items() if k in ("num_wl", "points_per_wl", "fn", "kg_frac")},
        )
        if source == GEOMETRY_HP:
            return hull
        if volumes_report is not None:
            return hull_from_volumes(vec, report=volumes_report, **hydro_kwargs)
        # soft: still try direct volumes once more, else project
        try:
            return hull_from_volumes(vec, report=None, **hydro_kwargs)
        except Exception:  # noqa: BLE001
            return project_to_hull(vec)
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
        use_hp_geometry: bool | None = None,
        use_hp_hydro: bool | None = None,
        hp_hydro_every_n: int | None = None,
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

        # HP primary geometry/hydro: default True when vendored Ship-D present.
        if use_hp_geometry is None:
            use_hp_geometry = hp_geometry_default()
        self.use_hp_geometry = bool(use_hp_geometry)

        # use_hp_hydro follows use_hp_geometry unless explicitly set.
        if use_hp_hydro is None:
            use_hp_hydro = self.use_hp_geometry
        self.use_hp_hydro = bool(use_hp_hydro)

        # When HP geometry is on, refresh volumes every accepted step by default.
        if hp_hydro_every_n is None:
            hp_hydro_every_n = 1 if self.use_hp_geometry else 0
        self.hp_hydro_every_n = int(hp_hydro_every_n)
        self.hp_num_wl = int(hp_num_wl)
        self.hp_points_per_wl = int(hp_points_per_wl)
        self._volumes_report = None
        self._geometry_source = GEOMETRY_FALLBACK
        self._lo, self._hi = load_action_bounds()
        self._scales = action_scales(self._lo, self._hi, delta_frac=self.delta_frac)
        self._constraint_report = evaluate_constraints(self.shipd_vector)
        if self.use_hp_hydro or self.use_hp_geometry:
            try:
                self._volumes_report = calc_volumes(
                    self.shipd_vector,
                    num_wl=self.hp_num_wl,
                    points_per_wl=self.hp_points_per_wl,
                )
                self._geometry_source = GEOMETRY_HP
            except Exception:  # noqa: BLE001
                self._volumes_report = None
                self._geometry_source = GEOMETRY_FALLBACK
        parent = hull_from_shipd(
            self.shipd_vector,
            use_hp_hydro=self.use_hp_hydro,
            use_hp_geometry=self.use_hp_geometry,
            volumes_report=self._volumes_report,
            num_wl=self.hp_num_wl,
            points_per_wl=self.hp_points_per_wl,
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
        if self.use_hp_hydro or self.use_hp_geometry:
            try:
                self._volumes_report = calc_volumes(
                    self.shipd_vector,
                    num_wl=self.hp_num_wl,
                    points_per_wl=self.hp_points_per_wl,
                )
                self._geometry_source = GEOMETRY_HP
            except Exception:  # noqa: BLE001
                self._volumes_report = None
                self._geometry_source = GEOMETRY_FALLBACK
        else:
            self._volumes_report = None
            self._geometry_source = GEOMETRY_FALLBACK
        self.parent = hull_from_shipd(
            self.shipd_vector,
            use_hp_hydro=self.use_hp_hydro,
            use_hp_geometry=self.use_hp_geometry,
            volumes_report=self._volumes_report,
            num_wl=self.hp_num_wl,
            points_per_wl=self.hp_points_per_wl,
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
        info["use_hp_geometry"] = self.use_hp_geometry
        info["use_hp_hydro"] = self.use_hp_hydro
        info["geometry_source"] = self._geometry_source
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
                "use_hp_geometry": self.use_hp_geometry,
                "geometry_source": self._geometry_source,
                "monitor": {
                    "allow": False,
                    "reason_codes": ["shipd_algebraic_constraints"],
                    "projected": None,
                },
            }
            return self._obs(), reward, terminated, truncated, info

        candidate_vec = ShipDVector(tuple(float(x) for x in proposed))
        # HP primary: refresh volumes every N accepted-path steps (default N=1).
        refresh_hp = (
            (self.use_hp_geometry or self.use_hp_hydro)
            and self.hp_hydro_every_n > 0
            and (self.step_count % self.hp_hydro_every_n == 0)
        )
        step_source = GEOMETRY_FALLBACK
        if refresh_hp:
            try:
                step_vol = calc_volumes(
                    candidate_vec,
                    num_wl=self.hp_num_wl,
                    points_per_wl=self.hp_points_per_wl,
                )
                projected = hull_from_shipd(
                    candidate_vec,
                    use_hp_hydro=True,
                    use_hp_geometry=True,
                    volumes_report=step_vol,
                    num_wl=self.hp_num_wl,
                    points_per_wl=self.hp_points_per_wl,
                )
                self._volumes_report = step_vol
                step_source = GEOMETRY_HP
                self._geometry_source = GEOMETRY_HP
            except Exception:  # noqa: BLE001
                projected = project_to_hull(candidate_vec)
                step_source = GEOMETRY_FALLBACK
                self._geometry_source = GEOMETRY_FALLBACK
        elif self.use_hp_geometry and self._volumes_report is not None:
            # Reuse last HP report only if every_n disabled mid-episode — still prefer HP hull
            # via cheap project only when HP refresh is off.
            projected = hull_from_shipd(candidate_vec, use_hp_hydro=False, use_hp_geometry=False)
            step_source = GEOMETRY_FALLBACK
        else:
            projected = hull_from_shipd(candidate_vec, use_hp_hydro=False, use_hp_geometry=False)
            step_source = GEOMETRY_FALLBACK

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
                "use_hp_geometry": self.use_hp_geometry,
                "geometry_source": step_source,
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
            "use_hp_geometry": self.use_hp_geometry,
            "use_hp_hydro": self.use_hp_hydro,
            "geometry_source": step_source,
            "monitor": {
                "allow": True,
                "reason_codes": [],
                "projected": self.state.to_dict(),
            },
        }
        if refresh_hp and self._volumes_report is not None:
            info["hp_hydro"] = self._volumes_report.to_dict()
        return self._obs(), reward, terminated, truncated, info
