"""Parity tests: Python L0/L1 vs Zig mirror via zig_bridge."""

from __future__ import annotations

import math

import pytest

from yard_sea_v0.hull import HullState, evaluate_l0
from yard_sea_v0.resistance_l1 import estimate_resistance
from yard_sea_v0.zig_bridge import (
    call_zig,
    evaluate_l0_zig,
    estimate_resistance_zig,
    zig_available,
)

pytestmark = pytest.mark.skipif(not zig_available(), reason="yard_sea_zig not built")


def test_default_l0_parity():
    h = HullState()
    py = evaluate_l0(h)
    zg = evaluate_l0_zig(h)
    assert zg["feasible"] is True
    assert py.feasible is True
    assert abs(zg["gm0_m"] - py.metrics["gm0_m"]) < 1e-9
    assert abs(zg["volume_m3"] - py.metrics["volume_m3"]) < 1e-9
    assert abs(zg["displacement_t"] - py.metrics["displacement_t"]) < 1e-9


def test_bad_cb_rejected_both():
    h = HullState(Cb=0.2)
    py = evaluate_l0(h)
    zg = evaluate_l0_zig(h)
    assert not py.feasible
    assert zg["feasible"] is False
    assert any("Cb" in v for v in zg["violations"])


def test_default_l1_parity():
    h = HullState()
    py = estimate_resistance(h)
    zg = estimate_resistance_zig(h)
    assert abs(zg.Cf - py.Cf) < 1e-12
    assert abs(zg.k1 - py.k1) < 1e-12
    assert abs(zg.Cw - py.Cw) < 1e-12
    assert abs(zg.Ct - py.Ct) < 1e-12
    assert abs(zg.Rt_N - py.Rt_N) < 1e-6
    assert abs(zg.Rn - py.Rn) < 1e-3


def test_both_mode_json_shape():
    data = call_zig(HullState(), mode="both")
    assert "l0" in data and "l1" in data
    assert data["l0"]["feasible"] is True
    assert data["l1"]["Ct"] > 0


def test_perturbed_hull_parity():
    h = HullState(L=140, B=22, T=7.5, Cb=0.7, lcb_frac=-0.01, kg_frac=0.5, Fn=0.18)
    py0 = evaluate_l0(h)
    zg0 = evaluate_l0_zig(h)
    assert py0.feasible == zg0["feasible"]
    assert abs(zg0["gm0_m"] - py0.metrics["gm0_m"]) < 1e-9
    py1 = estimate_resistance(h)
    zg1 = estimate_resistance_zig(h)
    assert math.isclose(zg1.Ct, py1.Ct, rel_tol=0, abs_tol=1e-12)
