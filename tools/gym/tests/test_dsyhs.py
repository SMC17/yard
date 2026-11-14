"""DSYHS (CC0, vendored derived CSV): measured C_T on yacht canoe bodies as an out-of-population check."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from yard_sea_v0 import dsyhs

REPORT = Path(__file__).resolve().parents[1] / "reports" / "validation" / "dsyhs_validation.json"


def test_water_properties():
    assert dsyhs.rho_fresh(4.0) == pytest.approx(999.97, abs=0.01)
    assert dsyhs.rho_fresh(20.0) == pytest.approx(998.21, abs=0.01)
    assert dsyhs.nu_fresh(15.0) == pytest.approx(1.1386e-6, rel=2e-3)


def test_vendored_points_sane():
    pts = dsyhs.load()
    assert len(pts) >= 450 and len({p["sysser"] for p in pts}) >= 30
    for p in pts:
        assert 1.5 <= p["lwl"] <= 2.1 and 0.05 < p["Fn"] < 0.8
        assert 1.5e-3 < p["CT"] < 6e-2  # hump region reaches ~0.046 (Sys 6, Fn 0.55)
        # canoe-body volume consistent with C_B * L * B * T
        assert p["volc"] == pytest.approx(p["cb"] * p["lwl"] * p["bwl"] * p["tc"], rel=0.02)


def test_applicability_flags_every_yacht_point():
    rep = json.loads(REPORT.read_text())
    assert rep["schema"] == dsyhs.DSYHS_SCHEMA
    # Yacht canoe bodies are outside the HM declared range; the advisory check must say so.
    assert rep["share_in_hm_declared_range"] == 0.0
    assert rep["share_in_tank_validated_envelope"] == 0.0
    hm = rep["per_oracle"]["hm1984_gym_bare"]["overall"]
    assert hm["n"] == rep["n_points"] and hm["median_abs_E_pct"] > 10.0
