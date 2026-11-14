"""Ship-D 45-D parametric schema + projection into Yard-Sea-v0 HullState.

Public labels from MIT DeCoDe Ship-D (Bagazinski & Ahmed). Full surface
generation and the 49 algebraic constraints are wrapped in
``yard_sea_v0.shipd_surface`` (vendored ``Hull_Parameterization``).

This module:

1. Names the 45 parameters and groups
2. Projects principal dimensions into our exploratory HullState for L0/L1
3. Loads sample vectors for regression tests / parent seeding
4. Documents / forwards the 49-constraint checklist to shipd_surface when available

See STATUS.md — not class / ITTC.
"""

from __future__ import annotations

from functools import lru_cache

import csv
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

import numpy as np

from .hull import HullState

_LABELS_PATH = Path(__file__).with_name("shipd_labels.json")


def load_schema() -> dict[str, Any]:
    return json.loads(_LABELS_PATH.read_text())


LABELS: list[str] = load_schema()["labels"]
assert len(LABELS) == 45


@dataclass(frozen=True)
class ShipDVector:
    """Validated length-45 Ship-D input vector (raw dataset scaling)."""

    values: tuple[float, ...]

    def __post_init__(self) -> None:
        if len(self.values) != 45:
            raise ValueError(f"Ship-D vector must be length 45, got {len(self.values)}")

    @classmethod
    def from_sequence(cls, seq: Sequence[float]) -> "ShipDVector":
        return cls(tuple(float(x) for x in seq))

    def as_dict(self) -> dict[str, float]:
        return {name: self.values[i] for i, name in enumerate(LABELS)}

    def principal(self) -> dict[str, float]:
        d = self.as_dict()
        loa = d["LOA"]
        # Match Ship-D Hull_Parameterization scaling (public source).
        bd_full = d["Bd"] * loa  # full deck beam
        dd = d["Dd"] * loa
        draft = d["WL"] * dd
        return {
            "LOA": loa,
            "Lb": d["Lb"] * loa,
            "Ls": d["Ls"] * loa,
            "Bd": bd_full,
            "Dd": dd,
            "Bs_frac": d["Bs"],
            "T": draft,
            "Bc": d["Bc"] * loa,
            "Beta": d["Beta"],
        }


def project_to_hull(
    vec: ShipDVector | Sequence[float],
    *,
    cb: float | None = None,
    fn: float = 0.20,
    kg_frac: float = 0.55,
    appendages: bool = False,
) -> HullState:
    """Project Ship-D principals into exploratory HullState for L0/L1.

    ``appendages=True`` also fills the Holtrop bulb / transom inputs
    (``abt_m2``, ``hb_m``, ``at_m2``) from the Ship-D geometry
    (``shipd_appendages``). Off by default so existing Ship-D rewards are unchanged.

    Midbody fullness is approximated from chine beam / deck beam when cb omitted.
    This is intentionally a *projection*, not a volume-accurate Ship-D → hydro map.
    """
    v = vec if isinstance(vec, ShipDVector) else ShipDVector.from_sequence(vec)
    p = v.principal()
    d = v.as_dict()
    L = max(p["LOA"], 1.0)
    B = max(p["Bd"], 0.5)
    T = max(p["T"], 0.2)
    if cb is None:
        # Bc is full chine beam scale ~ Bc*LOA in HP; use ratio to deck beam.
        bc_full = max(d["Bc"] * L, 1e-6)
        cb = min(0.95, max(0.45, 0.55 + 0.35 * min(1.0, bc_full / B)))
    # Parallel midbody fraction as soft LCB bias (bow vs stern taper lengths)
    mid_frac = max(0.0, 1.0 - d["Lb"] - d["Ls"])
    del mid_frac  # reserved for future volume map
    lcb_frac = 0.02 * (d["Ls"] - d["Lb"])  # more stern taper → LCB forward soft
    lcb_frac = max(-0.05, min(0.05, lcb_frac))
    h = HullState(
        L=L,
        B=B,
        T=T,
        Cb=cb,
        lcb_frac=lcb_frac,
        kg_frac=kg_frac,
        Fn=fn,
    )
    if appendages:
        app = shipd_appendages(tuple(v.values), T)
        h = HullState(**{**h.__dict__, **app})
    return h


@lru_cache(maxsize=4096)
def shipd_appendages(vec: tuple[float, ...], draft: float) -> dict[str, float]:
    """Holtrop A_BT / h_B / A_T read off a Ship-D hull (same definitions as ``hull_lines``).

    Ship-D x runs from the bow (0) to the stern (LOA). FP = first station where the
    design waterline has breadth; A_BT = submerged section area there (both sides),
    h_B its centroid height above the keel; A_T = submerged section area at the last
    station with any breadth (immersed transom). A_BT below 0.5 % of B*T is a stem
    sliver -> 0 (no bulb).
    """
    from .teachers.michell_l15 import shipd_waterline_offsets

    try:
        Y, X, Z = shipd_waterline_offsets(np.asarray(vec), nx=401, nz=41, draft=draft)
    except (np.linalg.LinAlgError, ValueError):
        # Upstream Ship-D geometry fails for some vectors: no bulb / transom terms (= bare).
        return {"abt_m2": 0.0, "hb_m": 0.0, "at_m2": 0.0}
    depth = -Z  # 0 at WL .. T at keel
    wl = np.nonzero(Y[:, 0] > 1e-9)[0]
    anyy = np.nonzero(Y.max(axis=1) > 1e-9)[0]
    out = {"abt_m2": 0.0, "hb_m": 0.0, "at_m2": 0.0}
    if wl.size == 0:
        return out
    B = 2.0 * float(Y[:, 0].max())
    yf = Y[wl[0]]
    abt = 2.0 * float(np.trapezoid(yf, depth))
    if abt > 0.005 * B * draft:
        out["abt_m2"] = abt
        out["hb_m"] = float(draft - 2.0 * np.trapezoid(yf * depth, depth) / abt)
    at = 2.0 * float(np.trapezoid(Y[anyy[-1]], depth))
    out["at_m2"] = at if at > 1e-4 * B * draft else 0.0
    return out


def load_sample_vectors(path: Path | None = None) -> list[ShipDVector]:
    """Load the public Ship-D sample CSV shipped with the gym."""
    if path is None:
        path = Path(__file__).parent / "data" / "shipd_sample_vectors.csv"
    out: list[ShipDVector] = []
    with path.open(newline="") as f:
        for row in csv.reader(f):
            if not row:
                continue
            vals = [float(x) for x in row]
            if len(vals) != 45:
                raise ValueError(f"expected 45 cols, got {len(vals)}")
            out.append(ShipDVector(tuple(vals)))
    return out


def constraint_checklist() -> dict[str, Any]:
    """Document the 49 algebraic constraints; evaluate via shipd_surface when present."""
    base: dict[str, Any] = {
        "n": 49,
        "purpose": ["watertight", "non_self_intersecting"],
        "implementation": "Hull_Parameterization.input_Constraints",
        "source": "https://github.com/noahbagz/ShipD",
        "vendor": "vendor/shipd_upstream/",
        "wrapper": "yard_sea_v0.shipd_surface.evaluate_constraints",
    }
    try:
        from .shipd_surface import N_CONSTRAINTS, upstream_available

        if upstream_available():
            base["status"] = "evaluated_via_shipd_surface"
            base["n_runtime"] = N_CONSTRAINTS
            return base
    except Exception as exc:  # pragma: no cover
        base["status"] = "import_error"
        base["error"] = str(exc)
        return base
    base["status"] = "upstream_missing"
    return base


def is_feasible(vec: ShipDVector | Sequence[float]) -> bool:
    """True iff Ship-D 49 algebraic constraints all pass (values <= 0)."""
    from .shipd_surface import evaluate_constraints

    return evaluate_constraints(vec).feasible


# --- 45-D action bounds (dataset percentiles) ---------------------------------

_BOUNDS_PATH = Path(__file__).parent / "data" / "shipd_action_bounds.json"
BIT_LABELS: tuple[str, ...] = ("bit_EP_S", "bit_EP_T", "bit_BB", "bit_SB")
BIT_INDICES: tuple[int, ...] = tuple(LABELS.index(n) for n in BIT_LABELS)


def load_action_bounds(
    path: Path | None = None,
    *,
    p_lo: float = 1.0,
    p_hi: float = 99.0,
) -> tuple[np.ndarray, np.ndarray]:
    """Return (lo, hi) length-45 arrays for clamping Ship-D actions.

    Prefers cached JSON from the 30k corpus; falls back to sample CSV percentiles
    or recomputes from ``InputVectors_30k.npy`` when present.
    """
    import numpy as np

    path = Path(path) if path is not None else _BOUNDS_PATH
    if path.is_file():
        data = json.loads(path.read_text())
        lo = np.asarray(data["lo"], dtype=np.float64)
        hi = np.asarray(data["hi"], dtype=np.float64)
        if lo.shape == (45,) and hi.shape == (45,):
            return lo, hi

    npy = Path(__file__).parent / "data" / "InputVectors_30k.npy"
    if npy.is_file():
        arr = np.load(npy)
        lo = np.percentile(arr, p_lo, axis=0).astype(np.float64)
        hi = np.percentile(arr, p_hi, axis=0).astype(np.float64)
        return lo, hi

    samples = load_sample_vectors()
    arr = np.asarray([list(s.values) for s in samples], dtype=np.float64)
    lo = np.min(arr, axis=0)
    hi = np.max(arr, axis=0)
    return lo, hi


def action_scales(
    lo: np.ndarray | None = None,
    hi: np.ndarray | None = None,
    *,
    delta_frac: float = 0.05,
) -> np.ndarray:
    """Per-dim absolute delta scale so action in [-1,1] moves ``delta_frac`` of span."""
    import numpy as np

    if lo is None or hi is None:
        lo, hi = load_action_bounds()
    span = np.maximum(hi - lo, 0.0)
    return span * float(delta_frac)
