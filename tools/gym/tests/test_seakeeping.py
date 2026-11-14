"""Seakeeping L2 (Capytaine zero-speed RAOs + far-field mean drift) and multi-condition score."""

from __future__ import annotations

import os

import numpy as np
import pytest

from yard_sea_v0.hull import HullState
from yard_sea_v0.seakeeping import (
    Condition,
    EXAMPLE_SEA_STATE,
    SeaState,
    accept_seakeeping,
    detect,
    evaluate_conditions,
    multi_condition_score,
    solve,
    spectral_added_resistance,
    waterplane_exponent,
)

_HAVE = detect()["available"]
needs_capytaine = pytest.mark.skipif(
    not _HAVE and os.environ.get("YARD_REQUIRE_CAPYTAINE") != "1",
    reason="capytaine>=3.0 not installed (optional L2 dependency)",
)
FAST = dict(omegas=tuple(np.linspace(0.25, 1.6, 10)), n_theta=121)  # auto mesh: 30x5x3 on 120 m


def test_spectrum_m0_matches_hs():
    sea = SeaState(Hs=3.0, Tp=9.0)
    w = np.linspace(0.05, 6.0, 6000)
    assert np.trapezoid(sea.spectrum(w), w) == pytest.approx(sea.m0(), rel=1e-3)
    peak = w[np.argmax(sea.spectrum(w))]
    assert peak == pytest.approx(2 * np.pi / 9.0, rel=0.01)


def test_waterplane_exponent_honours_cb():
    for cb in (0.5, 0.65, 0.75, 0.9):
        p = waterplane_exponent(cb)
        assert p / (p + 1) == pytest.approx(cb)


@pytest.fixture(scope="module")
def default_solution():
    if not _HAVE:
        pytest.skip("capytaine>=3.0 not installed")
    return solve(HullState(), **FAST)


@needs_capytaine
def test_physics_limits_and_acceptance(default_solution):
    s = default_solution
    assert not s["skipped"] and s["fidelity"] == "L2_seakeeping_zero_speed"
    spec = spectral_added_resistance(s, EXAMPLE_SEA_STATE)
    acc = accept_seakeeping(s, spec)
    assert acc.passed, acc.failed_checks
    raw = np.asarray(s["raw_per_zeta2_N_m2"])
    # added resistance peaks near motion resonance, well below the long-wave end
    assert int(np.argmax(raw)) > 0
    assert spec["mean_added_resistance_N"] > 0
    assert 4.0 < s["heave_natural_period_s_est"] < 15.0


@needs_capytaine
def test_coarse_mesh_fails_resolution_check():
    s = solve(HullState(), mesh_res=(12, 4, 3), omegas=(0.25, 1.0, 1.6), n_theta=61)
    assert "mesh_resolves_shortest_wave" in accept_seakeeping(s).failed_checks


@needs_capytaine
def test_narrow_omega_grid_fails_coverage(default_solution):
    swell = SeaState(Hs=2.0, Tp=20.0)  # energy mostly below the solved ω range
    spec = spectral_added_resistance(default_solution, swell)
    acc = accept_seakeeping(default_solution, spec)
    assert "spectral_coverage" in acc.failed_checks


@needs_capytaine
def test_blunt_box_short_wave_drift_near_reflection_limit():
    """Near-box hull: short-wave drift approaches ½ρgB (full reflection off a vertical bow)."""
    s = solve(HullState(Cb=0.95), mesh_res=(60, 8, 5), omegas=(0.3, 1.0, 1.4), n_theta=121)
    ratio = s["raw_per_zeta2_N_m2"][-1] / s["reflection_limit_N_m2"]
    assert 0.5 < ratio < 1.1


@needs_capytaine
def test_identical_hull_scores_zero_and_records_conditions():
    out = multi_condition_score(HullState(), HullState(), solve_kwargs=FAST)
    assert out["accepted"] and out["n_credited"] == 2
    assert out["score"] == pytest.approx(0.0, abs=1e-12)
    sea = out["points"][1]["child"]
    assert 0.0 < sea["added_fraction"] < 0.5


@needs_capytaine
def test_sea_condition_can_flip_a_calm_only_ranking():
    """The sea condition is a separate signal: its d_total differs from calm-water d_total."""
    parent, child = HullState(), HullState(Cb=0.85, L=110.0)
    out = multi_condition_score(child, parent, solve_kwargs=FAST)
    calm, sea = out["points"][0], out["points"][1]
    assert calm["credited"] and sea["credited"]
    assert sea["d_total"] != pytest.approx(calm["d_total"], abs=1e-3)


def test_missing_capytaine_is_pending_not_credited(monkeypatch):
    import yard_sea_v0.seakeeping as sk

    monkeypatch.setattr(sk, "detect", lambda: {"available": False, "error": "x"})
    ev = evaluate_conditions(HullState(), (Condition("calm"), Condition("sea", 1.0, EXAMPLE_SEA_STATE)))
    calm, sea = ev["conditions"]
    assert calm["accepted"] and calm["total_N"] > 0
    assert not sea["accepted"] and sea["total_N"] is None
    out = sk.multi_condition_score(HullState(Cb=0.7), HullState())
    assert out["n_credited"] == 1 and out["accepted"] is False
