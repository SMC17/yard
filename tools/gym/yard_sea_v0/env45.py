"""45-D Ship-D-aware design search env (principal subspace first).

Action space is still 7 floats (principal morph), but state tracks a full 45-D
Ship-D vector; non-principal dims hold from the parent sample.

Ship-D algebraic constraints (49) are evaluated on the seeded vector and
re-checked before L1: infeasible Ship-D seeds / vectors reject without
running resistance ranking.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from .env import DesignSearchEnv
from .shipd import LABELS, ShipDVector, load_sample_vectors, project_to_hull
from .shipd_surface import evaluate_constraints


class DesignSearchEnv45(DesignSearchEnv):
    """DesignSearchEnv seeded from Ship-D, exposing shipd_vector in info."""

    def __init__(self, sample_index: int = 0, **kwargs: Any) -> None:
        samples = load_sample_vectors()
        if sample_index < 0 or sample_index >= len(samples):
            raise IndexError(f"sample_index {sample_index} out of range 0..{len(samples)-1}")
        self.shipd_vector = samples[sample_index]
        self._constraint_report = evaluate_constraints(self.shipd_vector)
        parent = project_to_hull(self.shipd_vector)
        super().__init__(parent=parent, **kwargs)

    def reset(self, *, seed: int | None = None, options: dict | None = None):
        obs, info = super().reset(seed=seed, options=options)
        info["shipd_labels"] = LABELS
        info["shipd_vector"] = list(self.shipd_vector.values)
        info["shipd_principal"] = self.shipd_vector.principal()
        info["shipd_constraints"] = self._constraint_report.to_dict()
        info["shipd_feasible"] = self._constraint_report.feasible
        return obs, info

    def step(self, action):
        # Reject before L1 if the Ship-D seed fails algebraic constraints.
        if not self._constraint_report.feasible:
            action = list(np.asarray(action, dtype=float).reshape(-1))
            self.step_count += 1
            truncated = self.step_count >= self.max_steps
            reward = -1.0
            info = {
                "rejected": True,
                "shipd_infeasible": True,
                "shipd_constraints": self._constraint_report.to_dict(),
                "monitor": {
                    "allow": False,
                    "reason_codes": ["shipd_algebraic_constraints"],
                },
            }
            return self._obs(), reward, False, truncated, info
        return super().step(action)
