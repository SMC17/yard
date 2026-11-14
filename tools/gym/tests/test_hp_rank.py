"""HP-primary ranking path: calc_volumes + STL + Michell-from-HP."""

from __future__ import annotations

from pathlib import Path

import numpy as np

from yard_sea_v0.hp_rank import (
    GEOMETRY_FALLBACK,
    GEOMETRY_HP,
    hp_geometry_default,
    hull_from_shipd_primary,
    rank_shipd,
)
from yard_sea_v0.shipd import load_sample_vectors, project_to_hull
from yard_sea_v0.shipd_surface import upstream_available


def test_hp_geometry_default_matches_vendor():
    assert hp_geometry_default() is upstream_available()
    assert hp_geometry_default() is True


def test_hull_from_shipd_primary_uses_hp():
    vec = load_sample_vectors()[0]
    hull, src, volumes, reason = hull_from_shipd_primary(vec, prefer_hp=True)
    assert src == GEOMETRY_HP
    assert reason is None
    assert volumes is not None
    assert volumes.primary().volume_m3 > 0
    # HP Cb differs from algebraic project_to_hull
    proj = project_to_hull(vec)
    assert abs(hull.Cb - proj.Cb) > 1e-3 or abs(hull.lcb_frac - proj.lcb_frac) > 1e-4


def test_hull_from_shipd_primary_fallback_when_disabled():
    vec = load_sample_vectors()[0]
    hull, src, volumes, reason = hull_from_shipd_primary(vec, prefer_hp=False)
    assert src == GEOMETRY_FALLBACK
    assert volumes is None
    assert reason == "prefer_hp=False"
    assert hull.L == project_to_hull(vec).L


def test_rank_shipd_primary_path(tmp_path: Path):
    vec = load_sample_vectors()[0]
    stl = tmp_path / "rank0.stl"
    result = rank_shipd(
        vec,
        prefer_hp=True,
        use_michell=True,
        stl_path=stl,
        stl_num_wl=12,
        stl_points_per_wl=24,
        michell_kwargs={"nx": 21, "nz": 7, "n_theta": 12},
    )
    assert result.geometry_source == GEOMETRY_HP
    assert result.volumes is not None
    assert result.constraints is not None and result.constraints.feasible
    assert result.resistance_l1 is not None
    assert np.isfinite(result.ct) and result.ct > 0
    assert result.michell is not None
    assert result.michell.get("offset_source") == "shipd_hp_waterlines"
    assert result.michell.get("skipped") is False
    assert np.isfinite(result.michell["Cw"])
    assert result.stl_path is not None
    assert Path(result.stl_path).is_file()
    assert Path(result.stl_path).stat().st_size > 500
    d = result.to_dict()
    assert d["geometry_source"] == GEOMETRY_HP
    assert d["primary"] == "Hull_Parameterization"


def test_rank_shipd_fallback_path():
    vec = load_sample_vectors()[3]
    result = rank_shipd(vec, prefer_hp=False, use_michell=False, stl_path=None)
    assert result.geometry_source == GEOMETRY_FALLBACK
    assert result.volumes is None
    assert result.michell is None
    assert np.isfinite(result.ct)


def test_rank_multiple_samples_finite():
    samples = load_sample_vectors()
    for idx in (0, 3, 9):
        r = rank_shipd(
            samples[idx],
            use_michell=True,
            michell_kwargs={"nx": 21, "nz": 7, "n_theta": 10},
        )
        assert r.geometry_source == GEOMETRY_HP
        assert np.isfinite(r.ct)
        assert r.michell and np.isfinite(r.michell["Cw"])
