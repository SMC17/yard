"""Yard-Sea-v0: evidence-coupled parametric hull design-search gym."""

__version__ = "0.2.0"

from .env import DesignSearchEnv
from .env45 import ACTION_DIM, DesignSearchEnv45
from .hull import HullState, evaluate_l0

__all__ = [
    "ACTION_DIM",
    "DesignSearchEnv",
    "DesignSearchEnv45",
    "HullState",
    "evaluate_l0",
    "__version__",
]
