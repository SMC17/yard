"""Tests for Michell L1.5 wave-drag teacher."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

from yard_sea_v0.hull import HullState
from yard_sea_v0.shipd import load_sample_vectors, project_to_hull
from yard_sea_v0.teachers.michell_l15 import (
    FIDELITY,
    MichellAvailability,
    detect,
    run,
    shipd_waterline_offsets,
    wigley_offsets,
)


def test_detect_vendor_present():
    avail = detect()
    assert isinstance(avail, MichellAvailability)
    assert avail.available is True
    assert avail.path and avail.path.endswith("ModifiedMichellCw.py")


def test_wigley_offsets_shape_odd_nx():
    Y, X, Z = wigley_offsets(HullState(), nx=40, nz=9)
    assert Y.shape[0] % 2 == 1  # forced odd
    assert Y.shape == (X.size, Z.size)
    assert np.all(Y >= 0)
    assert Z[0] == pytest.approx(0.0)
    assert Z[-1] < 0


def test_run_returns_finite_cw():
    h = HullState(L=120.0, B=20.0, T=8.0, Cb=0.75, Fn=0.20)
    r = run(h, nx=31, nz=9, n_theta=20)
    assert r["skipped"] is False
    assert r["fidelity"] == FIDELITY
    assert r["teacher"] == "michell_l15"
    assert np.isfinite(r["Cw"])
    assert r["Cw"] > 0
    assert np.isfinite(r["Rw_N"])
    assert r["Rw_N"] > 0
    assert r["offset_source"] == "wigley_synthetic"
    assert "not ittc" in r["notes"].lower()


def test_run_skips_when_vendor_missing():
    fake = MichellAvailability(vendor_mod=False, path=None)
    r = run(HullState(), availability=fake)
    assert r["skipped"] is True
    assert r["skip_reason"] == "michell_vendor_missing"
    assert r["fidelity"] == "L1.5_pending"


def test_shipd_waterline_offsets_shape_and_positive():
    vec = load_sample_vectors()[0]
    Y, X, Z = shipd_waterline_offsets(vec, nx=30, nz=9)
    assert Y.shape[0] % 2 == 1
    assert Y.shape == (X.size, Z.size)
    assert X[0] == pytest.approx(0.0)
    assert X[-1] == pytest.approx(float(vec.principal()["LOA"]))
    assert Z[0] == pytest.approx(0.0)
    assert Z[-1] < 0
    assert np.all(Y >= 0)
    assert Y.max() > 0.05  # real half-breadth, not empty


def test_run_shipd_vector_finite_cw_differs_from_wigley():
    """Sample Ship-D vector → finite Cw; differs from Wigley projection fallback."""
    samples = load_sample_vectors()
    vec = samples[0]
    r_sd = run(vector=vec, Fn=0.20, nx=31, nz=9, n_theta=20)
    assert r_sd["skipped"] is False
    assert r_sd["offset_source"] == "shipd_hp_waterlines"
    assert r_sd["fidelity"] == FIDELITY
    assert np.isfinite(r_sd["Cw"]) and r_sd["Cw"] > 0
    assert np.isfinite(r_sd["Rw_N"]) and r_sd["Rw_N"] > 0

    h = project_to_hull(vec, fn=0.20)
    r_wig = run(h, Fn=0.20, nx=31, nz=9, n_theta=20)
    assert r_wig["offset_source"] == "wigley_synthetic"
    assert np.isfinite(r_wig["Cw"])
    # Real Ship-D waterlines should not collapse to the Wigley synthetic
    assert r_sd["Cw"] != pytest.approx(r_wig["Cw"], rel=1e-3)


def test_run_shipd_multiple_samples_finite():
    for idx in (0, 3, 9):
        vec = load_sample_vectors()[idx]
        r = run(vector=vec, Fn=0.25, nx=31, nz=9, n_theta=16)
        assert r["skipped"] is False, f"sample {idx} skipped: {r.get('skip_reason')}"
        assert r["offset_source"] == "shipd_hp_waterlines"
        assert np.isfinite(r["Cw"]) and r["Cw"] > 0


def test_cli_l15_flag(tmp_path: Path):
    from yard_sea_v0.cli import main

    rc = main(
        [
            "run-search",
            "--parents",
            "1",
            "--steps",
            "2",
            "--seed",
            "0",
            "--out",
            str(tmp_path / "gal"),
            "--l15-michell",
        ]
    )
    assert rc == 0
    import json

    manifest = json.loads((tmp_path / "gal" / "manifest.json").read_text())
    assert manifest["l15_michell"] is True
    assert manifest["l15_availability"]["available"] is True
    assert len(manifest["l15_summaries"]) >= 1
    assert all(s["fidelity"] == FIDELITY for s in manifest["l15_summaries"])


def test_cw_s_is_wetted_surface_basis_of_same_rw():
    from yard_sea_v0.hull import HullState
    from yard_sea_v0.teachers import michell_l15

    if not michell_l15.detect().available:
        import pytest

        pytest.skip("Michell vendor missing")
    h = HullState(Fn=0.25)
    r = michell_l15.run(h)
    ratio = r["Cw_S"] / r["Cw"]
    assert abs(ratio - r["L_m"] ** 2 / r["S_m2"]) < 1e-9 * ratio
    from yard_sea_v0.multi_froude import evaluate_point

    assert evaluate_point(h, 0.25, wave_oracle="michell").wave == r["Cw_S"]
