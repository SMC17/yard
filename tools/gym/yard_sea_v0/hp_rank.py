"""Primary Ship-D Hull_Parameterization geometry/hydro ranking path.

When a length-45 Ship-D vector is available, ranking prefers:

1. ``calc_volumes`` / ``hull_from_volumes`` (surface hydrostatics → HullState)
2. Ship-D STL via ``generate_stl`` / ``write_shipd_stl`` (optional path)
3. Michell L1.5 from HP waterlines (``teachers.michell_l15`` with ``vector=``)
4. L1 Holtrop-simplified resistance on the HP-refined HullState

``project_to_hull`` is **fallback only** (vendor missing or HP call failure).

Not ITTC powering / not class / not operational.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Sequence

import numpy as np

from .hull import HullState, evaluate_l0
from .resistance_l1 import ResistanceResult, estimate_resistance
from .shipd import ShipDVector, project_to_hull
from .shipd_surface import (
    DEFAULT_NUM_WL,
    DEFAULT_POINTS_PER_WL,
    ConstraintReport,
    VolumesReport,
    calc_volumes,
    evaluate_constraints,
    generate_stl,
    hull_from_volumes,
    upstream_available,
)


GEOMETRY_HP = "hp"
GEOMETRY_FALLBACK = "project_fallback"


def hp_geometry_default() -> bool:
    """True when vendored Hull_Parameterization is present (env45 default)."""
    return upstream_available()


def _as_vector(
    vector: Sequence[float] | ShipDVector | np.ndarray,
) -> ShipDVector:
    if isinstance(vector, ShipDVector):
        return vector
    return ShipDVector.from_sequence(np.asarray(list(vector), dtype=np.float64).reshape(-1))


@dataclass
class HPRankResult:
    """One ranking evaluation of a 45-D Ship-D vector."""

    hull: HullState
    geometry_source: str
    vector: list[float]
    volumes: VolumesReport | None = None
    constraints: ConstraintReport | None = None
    l0: Any = None
    resistance_l1: ResistanceResult | None = None
    michell: dict[str, Any] | None = None
    stl_path: str | None = None
    fallback_reason: str | None = None
    notes: list[str] = field(default_factory=list)

    @property
    def ct(self) -> float:
        if self.resistance_l1 is not None:
            return float(self.resistance_l1.Ct)
        return float("nan")

    @property
    def feasible(self) -> bool:
        if self.constraints is not None and not self.constraints.feasible:
            return False
        if self.l0 is not None and not self.l0.feasible:
            return False
        return True

    def to_dict(self) -> dict[str, Any]:
        return {
            "geometry_source": self.geometry_source,
            "fallback_reason": self.fallback_reason,
            "vector": list(self.vector),
            "hull": self.hull.to_dict(),
            "ct": self.ct,
            "feasible": self.feasible,
            "volumes": self.volumes.to_dict() if self.volumes is not None else None,
            "constraints": self.constraints.to_dict() if self.constraints is not None else None,
            "l0": self.l0.to_dict() if self.l0 is not None else None,
            "resistance_l1": self.resistance_l1.to_dict() if self.resistance_l1 else None,
            "michell": self.michell,
            "stl_path": self.stl_path,
            "notes": list(self.notes),
            "primary": "Hull_Parameterization",
            "honesty": "not ITTC / not class / exploratory ranking only",
        }


def hull_from_shipd_primary(
    vector: Sequence[float] | ShipDVector | np.ndarray,
    *,
    prefer_hp: bool = True,
    volumes_report: VolumesReport | None = None,
    num_wl: int = DEFAULT_NUM_WL,
    points_per_wl: int = DEFAULT_POINTS_PER_WL,
    fn: float = 0.20,
    kg_frac: float = 0.55,
) -> tuple[HullState, str, VolumesReport | None, str | None]:
    """Build HullState preferring HP calc_volumes; project_to_hull on failure.

    Returns (hull, geometry_source, volumes_or_none, fallback_reason_or_none).
    """
    vec = _as_vector(vector)
    if prefer_hp and upstream_available():
        try:
            report = volumes_report
            if report is None:
                report = calc_volumes(
                    vec, num_wl=num_wl, points_per_wl=points_per_wl
                )
            hull = hull_from_volumes(
                vec, report, fn=fn, kg_frac=kg_frac, num_wl=num_wl, points_per_wl=points_per_wl
            )
            return hull, GEOMETRY_HP, report, None
        except Exception as exc:  # noqa: BLE001 — intentional soft fallback
            reason = f"hp_failed:{type(exc).__name__}:{exc}"
            return (
                project_to_hull(vec, fn=fn, kg_frac=kg_frac),
                GEOMETRY_FALLBACK,
                None,
                reason,
            )
    reason = None if prefer_hp else "prefer_hp=False"
    if prefer_hp and not upstream_available():
        reason = "shipd_upstream_missing"
    return project_to_hull(vec, fn=fn, kg_frac=kg_frac), GEOMETRY_FALLBACK, None, reason


def rank_shipd(
    vector: Sequence[float] | ShipDVector | np.ndarray,
    *,
    prefer_hp: bool = True,
    use_michell: bool = True,
    stl_path: Path | str | None = None,
    volumes_report: VolumesReport | None = None,
    num_wl: int = DEFAULT_NUM_WL,
    points_per_wl: int = DEFAULT_POINTS_PER_WL,
    stl_num_wl: int = 24,
    stl_points_per_wl: int = 48,
    fn: float = 0.20,
    check_constraints: bool = True,
    michell_kwargs: dict[str, Any] | None = None,
) -> HPRankResult:
    """Rank a 45-D Ship-D vector via HP geometry/hydro (primary) + L1 (+ Michell).

    Parameters
    ----------
    prefer_hp
        When True (default), use calc_volumes / hull_from_volumes. On failure or
        missing vendor, fall back to ``project_to_hull``.
    use_michell
        Attach Michell L1.5 using HP waterlines when vector drives offsets.
    stl_path
        If set, write Ship-D surface STL via ``generate_stl`` (HP primary).
    """
    vec = _as_vector(vector)
    notes: list[str] = []
    constraints = evaluate_constraints(vec) if check_constraints else None

    hull, source, volumes, fallback_reason = hull_from_shipd_primary(
        vec,
        prefer_hp=prefer_hp,
        volumes_report=volumes_report,
        num_wl=num_wl,
        points_per_wl=points_per_wl,
        fn=fn,
    )
    if source == GEOMETRY_FALLBACK:
        notes.append(f"geometry_fallback:{fallback_reason}")
    else:
        notes.append("geometry:Hull_Parameterization.calc_volumes")

    l0 = evaluate_l0(hull)
    res = estimate_resistance(hull)

    michell_out: dict[str, Any] | None = None
    if use_michell:
        from .teachers.michell_l15 import run as run_michell

        kw = dict(michell_kwargs or {})
        # Prefer HP waterlines from the vector; pass HP-refined hull for S/Fn.
        michell_out = run_michell(hull, vector=vec, Fn=fn, **kw)
        notes.append(
            f"michell_offset_source:{michell_out.get('offset_source', 'unknown')}"
        )

    out_stl: str | None = None
    if stl_path is not None:
        try:
            if source == GEOMETRY_HP and upstream_available():
                p = generate_stl(
                    vec,
                    Path(stl_path),
                    num_wl=stl_num_wl,
                    points_per_wl=stl_points_per_wl,
                    require_feasible=bool(constraints.feasible) if constraints else False,
                )
                out_stl = str(p)
                notes.append("stl:shipd_hp_surface")
            else:
                # Fallback mesh: export projected box/taper principals only if asked
                from .mesh import export_hull_stl

                p, backend = export_hull_stl(hull, Path(stl_path))
                out_stl = str(p)
                notes.append(f"stl_fallback:{backend}")
        except Exception as exc:  # noqa: BLE001
            notes.append(f"stl_failed:{type(exc).__name__}:{exc}")

    return HPRankResult(
        hull=hull,
        geometry_source=source,
        vector=list(vec.values),
        volumes=volumes,
        constraints=constraints,
        l0=l0,
        resistance_l1=res,
        michell=michell_out,
        stl_path=out_stl,
        fallback_reason=fallback_reason,
        notes=notes,
    )


def rank_many(
    vectors: Sequence[Sequence[float] | ShipDVector | np.ndarray],
    **kwargs: Any,
) -> list[HPRankResult]:
    """Rank a batch of 45-D vectors (stable order)."""
    return [rank_shipd(v, **kwargs) for v in vectors]
