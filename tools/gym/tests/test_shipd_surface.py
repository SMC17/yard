"""Ship-D constraint eval + STL generation (vendored Hull_Parameterization)."""

from __future__ import annotations

from pathlib import Path

import numpy as np

from yard_sea_v0.shipd import constraint_checklist, is_feasible, load_sample_vectors
from yard_sea_v0.shipd_surface import (
    N_CONSTRAINTS,
    evaluate_constraints,
    generate_stl,
    upstream_available,
)
from yard_sea_v0.mesh import write_shipd_stl


def test_upstream_present():
    assert upstream_available()
    c = constraint_checklist()
    assert c["n"] == 49
    assert c["status"] == "evaluated_via_shipd_surface"


def test_constraints_on_all_samples():
    samples = load_sample_vectors()
    assert len(samples) >= 3
    ok = 0
    for v in samples:
        report = evaluate_constraints(v)
        assert len(report.values) == N_CONSTRAINTS == 49
        assert len(report.violated) == 49
        assert report.n_violations == sum(report.violated)
        assert report.feasible == (report.n_violations == 0)
        assert sum(report.group_violations.values()) == report.n_violations
        if report.feasible:
            ok += 1
            assert is_feasible(v)
    assert ok == len(samples)  # public samples are all feasible


def test_infeasible_vector_flags():
    samples = load_sample_vectors()
    bad = list(samples[0].values)
    # Force Lb + Ls > 1 so general hullform constraint LOA < Lb+Ls trips
    bad[1] = 0.9  # Lb fraction
    bad[2] = 0.9  # Ls fraction
    report = evaluate_constraints(bad)
    assert not report.feasible
    assert report.n_violations >= 1
    assert report.group_violations.get("general", 0) >= 1


def test_generate_stl_from_sample(tmp_path: Path):
    samples = load_sample_vectors()
    # Prefer a no-bulb sample for speed/robustness; any feasible works
    vec = samples[3]
    assert evaluate_constraints(vec).feasible
    out = generate_stl(
        vec,
        tmp_path / "hull_sample3.stl",
        num_wl=16,
        points_per_wl=30,
        require_feasible=True,
    )
    assert out.is_file()
    assert out.stat().st_size > 1000
    raw = out.read_bytes()
    # binary or ascii STL from numpy-stl
    assert raw[:5] == b"solid" or len(raw) > 84


def test_write_shipd_stl_mesh_api(tmp_path: Path):
    vec = load_sample_vectors()[9]
    p = write_shipd_stl(vec, tmp_path / "via_mesh.stl", num_wl=12, points_per_wl=24)
    assert p.is_file() and p.stat().st_size > 500


def test_generate_stl_rejects_infeasible(tmp_path: Path):
    bad = list(load_sample_vectors()[0].values)
    bad[1], bad[2] = 0.95, 0.95
    try:
        generate_stl(bad, tmp_path / "nope.stl", num_wl=8, points_per_wl=16)
        assert False, "expected ValueError"
    except ValueError as e:
        assert "infeasible" in str(e).lower()
