"""45-D Ship-D-aware design search env (principal subspace first).

Action space is still 7 floats (principal morph), but state tracks a full 45-D
Ship-D vector; non-principal dims hold from the parent sample. Full 45-D action
+ algebraic constraints land when Hull_Parameterization is optional-deps wired.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from .env import DesignSearchEnv
from .hull import HullState
from .shipd import LABELS, ShipDVector, load_sample_vectors, project_to_hull


class DesignSearchEnv45(DesignSearchEnv):
    """DesignSearchEnv seeded from Ship-D, exposing shipd_vector in info."""

    def __init__(self, sample_index: int = 0, **kwargs: Any) -> None:
        samples = load_sample_vectors()
        if sample_index < 0 or sample_index >= len(samples):
            raise IndexError(f"sample_index {sample_index} out of range 0..{len(samples)-1}")
        self.shipd_vector = samples[sample_index]
        parent = project_to_hull(self.shipd_vector)
        super().__init__(parent=parent, **kwargs)

    def reset(self, *, seed: int | None = None, options: dict | None = None):
        obs, info = super().reset(seed=seed, options=options)
        info["shipd_labels"] = LABELS
        info["shipd_vector"] = list(self.shipd_vector.values)
        info["shipd_principal"] = self.shipd_vector.principal()
        return obs, info
