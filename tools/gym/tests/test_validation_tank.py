"""Oracle validation vs towing-tank data (yard_sea_v0.validation)."""

import json
import math
from pathlib import Path

import pytest

from yard_sea_v0 import validation as V
from yard_sea_v0.zig_bridge import zig_available

REPORT = Path(__file__).resolve().parents[1] / "reports" / "validation" / "oracle_tank_validation.json"


def test_tank_cases_reproduce_published_reynolds_numbers():
    cases = V.tank_cases()
    assert len(cases) == 11
    kcs = [c for c in cases if c.hull == "KCS"]
    # Tokyo 2015 Case 2.1 lists Re = 5.23e6 ... 1.36e7
    for c, re in zip(kcs, (5.23e6, 7.33e6, 9.42e6, 1.10e7, 1.26e7, 1.36e7)):
        assert math.isclose(c.Re, re, rel_tol=0.01), (c.Fn, c.Re, re)
    jbc = [c for c in cases if c.hull == "JBC"][0]
    assert math.isclose(jbc.Re, 7.46e6, rel_tol=0.01)


def test_comparison_error_sign_is_ittc_convention():
    assert V.comparison_error_pct(4.0e-3, 3.8e-3) == pytest.approx(5.0)
    assert V.comparison_error_pct(4.0e-3, 4.4e-3) == pytest.approx(-10.0)


def test_simplified_py_validates_without_zig():
    rep = V.validate(["simplified_py"])
    st = rep["per_oracle"]["simplified_py"]
    assert st["overall"]["n"] == 11
    assert 0.0 < st["overall"]["mean_abs_E_pct"] < 30.0
    assert st["envelope"]["n_validated"] + st["envelope"]["n_failed"] == 11


def test_drift_threshold_zero_for_identical_error_structure():
    rows = [
        {"hull": "A", "Fn": 0.2, "oracles": {"a": {"E_pct": 5.0}, "b": {"E_pct": 5.0}}},
        {"hull": "B", "Fn": 0.22, "oracles": {"a": {"E_pct": -3.0}, "b": {"E_pct": -3.0}}},
    ]
    d = V.drift_threshold_from_validation({"rows": rows}, "a", "b")
    assert d["threshold"] == 0.0 and d["n_pairs"] == 2


def test_drift_threshold_first_order_propagation():
    # a's error changes by 10 points between hulls, b's by 2 -> disagreement 0.08
    rows = [
        {"hull": "A", "Fn": 0.2, "oracles": {"a": {"E_pct": 0.0}, "b": {"E_pct": 0.0}}},
        {"hull": "B", "Fn": 0.2, "oracles": {"a": {"E_pct": 10.0}, "b": {"E_pct": 2.0}}},
        {"hull": "C", "Fn": 0.5, "oracles": {"a": {"E_pct": 90.0}, "b": {"E_pct": 0.0}}},  # outside dFn
    ]
    d = V.drift_threshold_from_validation({"rows": rows}, "a", "b", quantile=1.0)
    assert d["threshold"] == pytest.approx(0.08) and d["n_pairs"] == 2
    assert V.drift_threshold_from_validation({"rows": rows}, "a", "b", same_hull_only=True)["n_pairs"] == 0


@pytest.mark.skipif(not zig_available(), reason="zig_gym binary not built")
def test_hm1984_full_runs_on_every_tank_point():
    for c in V.tank_cases():
        p = V.hm1984_full(c)
        assert p["available"] and 2e-3 < p["CT"] < 9e-3 and p["one_plus_k"] > 1.0


@pytest.mark.skipif(not zig_available(), reason="zig_gym binary not built")
def test_committed_report_is_reproducible():
    from yard_sea_v0 import hull_lines

    if not all(hull_lines.available(h) for h in hull_lines.HULLS):
        pytest.skip("report was generated with the hull lines fetched (python data/fetch/fetch_yard_data.py)")
    committed = json.loads(REPORT.read_text())
    fresh = V.validate()
    for o, s in fresh["per_oracle"].items():
        a, b = s["overall"], committed["per_oracle"][o]["overall"]
        assert a["n"] == b["n"], o
        assert a["mean_abs_E_pct"] == pytest.approx(b["mean_abs_E_pct"], abs=1e-6), o


def test_committed_report_has_envelopes_and_drift_thresholds():
    rep = json.loads(REPORT.read_text())
    assert rep["schema"] == V.VALIDATION_SCHEMA and rep["n_points"] == 11
    for o in ("hm1984_gym", "simplified_py", "michell_l15"):
        assert "box" in rep["per_oracle"][o]["envelope"]
    pairs = {(d["seen"], d["holdout"]): d for d in rep["drift_thresholds"]}
    assert pairs[("hm1984_gym", "michell_l15")]["threshold"] > 0


def test_michell_on_real_lines_reported():
    from yard_sea_v0 import hull_lines

    if not all(hull_lines.available(h) for h in hull_lines.HULLS):
        pytest.skip("hull lines not fetched")
    rep = json.loads((Path(__file__).resolve().parents[1] / "reports" / "validation" / "oracle_tank_validation.json").read_text())
    ml = rep["per_oracle"]["michell_lines"]
    assert ml["overall"]["n"] == 10  # every point except JBC (no lines)
    # Thin-ship on real full-form lines over-predicts: documented, not hidden.
    assert ml["overall"]["mean_E_pct"] < -20.0
