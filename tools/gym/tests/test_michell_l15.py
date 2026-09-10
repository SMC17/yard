"""Tests for Michell L1.5 wave-drag teacher."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

from yard_sea_v0.hull import HullState
from yard_sea_v0.teachers.michell_l15 import (
    FIDELITY,
    MichellAvailability,
    detect,
    run,
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
    assert "not ittc" in r["notes"].lower()


def test_run_skips_when_vendor_missing():
    fake = MichellAvailability(vendor_mod=False, path=None)
    r = run(HullState(), availability=fake)
    assert r["skipped"] is True
    assert r["skip_reason"] == "michell_vendor_missing"
    assert r["fidelity"] == "L1.5_pending"


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
