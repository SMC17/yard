"""Ship-D surface: 49 algebraic constraints + STL via vendored Hull_Parameterization.

Wraps public upstream https://github.com/noahbagz/ShipD (vendored under
vendor/shipd_upstream/). Feasibility rule matches upstream README:

    constraints = Hull.input_Constraints()
    feasible iff sum(constraints > 0) == 0

This is watertight / non-self-intersecting algebra — not class / ITTC.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Sequence

import numpy as np

from .hull import HullState
from .shipd import LABELS, ShipDVector, project_to_hull

_VENDOR = Path(__file__).resolve().parents[1] / "vendor" / "shipd_upstream"

CONSTRAINT_GROUPS: tuple[tuple[str, int], ...] = (
    ("general", 2),
    ("cross_section", 7),
    ("bow", 15),
    ("stern", 12),
    ("bulb", 13),
)
N_CONSTRAINTS = sum(n for _, n in CONSTRAINT_GROUPS)
assert N_CONSTRAINTS == 49


def upstream_available() -> bool:
    return (_VENDOR / "HullParameterization.py").is_file()


def _ensure_vendor_on_path() -> None:
    root = str(_VENDOR)
    if root not in sys.path:
        sys.path.insert(0, root)


def _hull_param(vector: Sequence[float] | ShipDVector | np.ndarray):
    if not upstream_available():
        raise ImportError(
            f"Ship-D upstream missing at {_VENDOR}; expected HullParameterization.py"
        )
    _ensure_vendor_on_path()
    from HullParameterization import Hull_Parameterization as HP  # type: ignore

    if isinstance(vector, ShipDVector):
        arr = np.asarray(vector.values, dtype=np.float64)
    else:
        arr = np.asarray(list(vector), dtype=np.float64)
    if arr.shape != (45,):
        raise ValueError(f"Ship-D vector must be length 45, got shape {arr.shape}")
    return HP(arr)


@dataclass(frozen=True)
class ConstraintReport:
    """Report from Hull_Parameterization.input_Constraints (49 floats)."""

    values: tuple[float, ...]
    violated: tuple[bool, ...]
    n_violations: int
    feasible: bool
    group_violations: dict[str, int] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "n": len(self.values),
            "n_violations": self.n_violations,
            "feasible": self.feasible,
            "violated": list(self.violated),
            "values": list(self.values),
            "group_violations": dict(self.group_violations),
            "source": "Hull_Parameterization.input_Constraints",
            "rule": "feasible iff all values <= 0 (upstream: sum(c > 0) == 0)",
        }


def evaluate_constraints(
    vector: Sequence[float] | ShipDVector | np.ndarray,
) -> ConstraintReport:
    """Evaluate the 49 algebraic Ship-D constraints on a length-45 vector."""
    hull = _hull_param(vector)
    raw = np.asarray(hull.input_Constraints(), dtype=np.float64).reshape(-1)
    if raw.size != N_CONSTRAINTS:
        raise RuntimeError(
            f"expected {N_CONSTRAINTS} constraints from upstream, got {raw.size}"
        )
    violated = tuple(bool(v > 0.0) for v in raw)
    n_viol = sum(violated)
    group_viol: dict[str, int] = {}
    i = 0
    for name, n in CONSTRAINT_GROUPS:
        group_viol[name] = sum(violated[i : i + n])
        i += n
    return ConstraintReport(
        values=tuple(float(x) for x in raw),
        violated=violated,
        n_violations=int(n_viol),
        feasible=n_viol == 0,
        group_violations=group_viol,
    )


def generate_stl(
    vector: Sequence[float] | ShipDVector | np.ndarray,
    path: Path | str,
    *,
    num_wl: int = 40,
    points_per_wl: int = 120,
    add_transom: bool = True,
    add_deck_lid: bool = True,
    require_feasible: bool = True,
) -> Path:
    """Generate a Ship-D surface STL via upstream gen_stl.

    ``path`` may be with or without ``.stl``; upstream appends ``.stl`` to namepath.
    Returns the final ``.stl`` Path.
    """
    path = Path(path)
    if require_feasible:
        report = evaluate_constraints(vector)
        if not report.feasible:
            raise ValueError(
                f"Ship-D vector infeasible: {report.n_violations}/49 constraints violated"
            )
    path.parent.mkdir(parents=True, exist_ok=True)
    # Upstream saves namepath + '.stl'
    if path.suffix.lower() == ".stl":
        namepath = path.with_suffix("")
        out = path
    else:
        namepath = path
        out = Path(str(path) + ".stl")
    hull = _hull_param(vector)
    hull.gen_stl(
        NUM_WL=int(num_wl),
        PointsPerWL=int(points_per_wl),
        bit_AddTransom=1 if add_transom else 0,
        bit_AddDeckLid=1 if add_deck_lid else 0,
        namepath=str(namepath),
    )
    if not out.is_file():
        raise FileNotFoundError(f"upstream gen_stl did not write {out}")
    return out


def to_hull_state(
    vector: Sequence[float] | ShipDVector | np.ndarray,
    **kwargs: Any,
) -> HullState:
    """Project Ship-D vector to exploratory HullState (same as shipd.project_to_hull)."""
    return project_to_hull(vector, **kwargs)


def labels_from_upstream() -> list[str]:
    """Load X_LABELS.npy from vendor (string list of 45 names)."""
    arr = np.load(_VENDOR / "X_LABELS.npy", allow_pickle=True)
    names = [str(x) for x in arr.tolist()]
    if names != LABELS:
        # Prefer gym schema; warn via return of upstream for diagnostics
        pass
    return names
