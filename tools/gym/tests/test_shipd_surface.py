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


def test_calc_volumes_sample_vectors():
    from yard_sea_v0.shipd import project_to_hull
    from yard_sea_v0.shipd_surface import (
        calc_volumes,
        clear_volumes_cache,
        hull_from_volumes,
    )

    clear_volumes_cache()
    samples = load_sample_vectors()
    for idx in (0, 1, 3, 9):
        v = samples[idx]
        report = calc_volumes(v, use_cache=True)
        assert report.num_wl == 41
        assert len(report.z) == 41 == len(report.volumes)
        st = report.primary()
        assert abs(st.z - float(v.principal()["T"])) < 1e-12
        assert st.volume_m3 > 0
        assert st.displacement_t > 0
        assert np.isfinite(st.lcb_m) and np.isfinite(st.vcb_m)
        assert st.awp_m2 > 0 and st.lwl_m > 0
        assert st.ixx_m4 >= 0 and st.iyy_m4 >= 0
        assert st.cb is not None and st.cb > 0
        # Shallow-WL samples (e.g. idx 3) can have tiny box-Cb; deeper drafts stay sane
        if st.z > 0.2 * report.dd:
            assert 0.2 < st.cb < 1.2
        d = report.to_dict()
        assert d["primary"]["displacement_t"] == st.displacement_t
        assert "cost_note" in d
        hull = hull_from_volumes(v, report)
        assert abs(hull.T - project_to_hull(v).T) < 1e-12
        assert abs(hull.Cb - float(max(0.35, min(0.98, st.cb)))) < 1e-12


def test_calc_volumes_multi_draft_and_cache():
    from yard_sea_v0.shipd_surface import calc_volumes, clear_volumes_cache

    clear_volumes_cache()
    v = load_sample_vectors()[0]
    dd = float(v.principal()["Dd"])
    drafts = [0.25 * dd, 0.5 * dd, float(v.principal()["T"])]
    r1 = calc_volumes(v, drafts=drafts, use_cache=True)
    assert len(r1.stations) == 3
    assert r1.stations[0].volume_m3 <= r1.stations[1].volume_m3 + 1e-9
    assert r1.stations[1].volume_m3 <= r1.stations[2].volume_m3 + 1e-9
    assert r1.cached is False
    r2 = calc_volumes(v, drafts=drafts[0], use_cache=True)
    assert r2.cached is True
    assert abs(r2.primary().volume_m3 - r1.stations[0].volume_m3) < 1e-9


def test_calc_volumes_scalar_draft():
    from yard_sea_v0.shipd_surface import calc_volumes, clear_volumes_cache

    clear_volumes_cache()
    v = load_sample_vectors()[0]
    z = 0.4 * float(v.principal()["Dd"])
    r = calc_volumes(v, drafts=z)
    assert len(r.stations) == 1
    assert abs(r.primary().z - z) < 1e-12
