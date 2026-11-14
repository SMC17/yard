"""Acceptance gate + measure-then-claim tests."""

from __future__ import annotations

from pathlib import Path

import numpy as np

from yard_sea_v0.acceptance import (
    accept_force_coeffs_file,
    accept_force_history,
    accept_l1,
    is_accepted,
    parse_force_coeffs_history,
)
from yard_sea_v0.env import DesignSearchEnv
from yard_sea_v0.hull import HullState
from yard_sea_v0.resistance_l1 import estimate_resistance
from yard_sea_v0.strip_assurance import strip_overlay

FIX = Path(__file__).parent / "fixtures"


def _write_history(path: Path, cd, cl, cm) -> Path:
    lines = ["# Force coefficients", "# Time    Cd    Cl    CmPitch"]
    for i, (a, b, c) in enumerate(zip(cd, cl, cm), start=1):
        lines.append(f"{i} {a:.8f} {b:.8f} {c:.8f}")
    path.write_text("\n".join(lines) + "\n")
    return path


def _settled(n=200, final=0.1, tau=10.0):
    t = np.arange(n, dtype=float)
    return final * (1.0 + np.exp(-t / tau))


def test_parse_history_expanded_header_maps_cmpitch():
    hist = parse_force_coeffs_history(FIX / "forceCoeffs.dat")
    assert hist is not None
    assert {"time", "Cd", "Cl", "Cm"} <= set(hist)
    assert len(hist["Cd"]) == len(hist["Cl"]) == len(hist["Cm"]) >= 3


def test_short_fixture_is_not_accepted():
    """Three iterations cannot demonstrate settling; the number must not be credited."""
    acc = accept_force_coeffs_file(FIX / "forceCoeffs.dat")
    assert acc.passed is False
    assert "Cd_settled" in acc.failed_checks


def test_all_coefficients_settled_passes(tmp_path):
    p = _write_history(tmp_path / "fc.dat", _settled(), _settled(final=0.01), _settled(final=-0.02))
    acc = accept_force_coeffs_file(p)
    assert acc.passed, acc.to_dict()
    d = acc.to_dict()
    assert d["schema"] == "yard_sea_v0.acceptance.v1"
    assert d["passed"] is True and d["failed_checks"] == []


def test_settled_drag_but_drifting_lift_fails(tmp_path):
    """Converged Cd alone is not acceptance: a drifting Cl/Cm must fail the gate."""
    n = 200
    cl_drift = 0.01 + 0.0005 * np.arange(n)  # still climbing at the end
    p = _write_history(tmp_path / "fc.dat", _settled(n), cl_drift, _settled(n, final=-0.02))
    acc = accept_force_coeffs_file(p)
    assert acc.passed is False
    assert acc.failed_checks == ["Cl_settled"]


def test_near_zero_coefficient_uses_abs_floor():
    n = 100
    hist = {"Cd": list(_settled(n)), "Cl": [1e-7 * ((-1) ** i) for i in range(n)], "Cm": list(_settled(n))}
    assert accept_force_history(hist).passed


def test_missing_coefficient_fails():
    hist = {"Cd": list(_settled(100))}
    acc = accept_force_history(hist)
    assert not acc.passed
    assert set(acc.failed_checks) == {"Cl_present", "Cm_present"}


def test_nonfinite_history_fails():
    s = list(_settled(100))
    s[-1] = float("nan")
    acc = accept_force_history({"Cd": s, "Cl": list(_settled(100)), "Cm": list(_settled(100))})
    assert "Cd_settled" in acc.failed_checks


def test_l1_acceptance_default_hull_passes_and_out_of_envelope_fails():
    assert accept_l1(estimate_resistance(HullState())).passed
    bad = estimate_resistance(HullState()).to_dict()
    bad["Fn"] = 0.6
    acc = accept_l1(bad)
    assert not acc.passed and "Fn_in_envelope" in acc.failed_checks


def test_is_accepted_requires_explicit_pass():
    assert not is_accepted(None)
    assert not is_accepted({"Cd": 0.1})
    assert not is_accepted({"acceptance": {"passed": False}})
    assert is_accepted({"acceptance": {"passed": True}})


def test_step_info_and_evidence_carry_acceptance():
    env = DesignSearchEnv(parent=HullState(), max_steps=3, seed=0)
    env.reset()
    _, _, _, _, info = env.step([0.1, 0, 0, 0, 0, 0, 0])
    assert info["acceptance"]["passed"] is True
    pack = env.evidence_packs[-1]
    assert pack["acceptance"]["passed"] is True
    assert pack["strip_assurance"]["validation_gates"]["acceptance_l1"] is True


def test_overlay_rejects_failed_acceptance():
    pack = {
        "monitor": {"allow": True},
        "l0": {"feasible": True},
        "resistance": {"Ct": 0.003},
        "acceptance": {"passed": False},
    }
    ov = strip_overlay(pack)
    assert ov["disposition"] == "reject_acceptance_gate"
    assert ov["validation_gates"]["resistance_l1"] is False


def _improve(env, n=10):
    """Shrink Cb a little each step (lower Ct for the default hull)."""
    a = np.zeros(7, dtype=np.float32)
    a[3] = -0.3
    for _ in range(n):
        env.step(a)


def test_claim_done_accepts_only_fresh_measurement():
    env = DesignSearchEnv(parent=HullState(), max_steps=20, seed=1)
    env.reset()
    _improve(env)
    true_ct = estimate_resistance(env.state).Ct
    assert true_ct < env.parent_ct
    ok = env.claim_done({"Ct": true_ct})
    assert ok["accepted"] is True, ok["reasons"]
    lie = env.claim_done({"Ct": true_ct * 0.9})
    assert lie["accepted"] is False
    assert any(r.startswith("claim_mismatch") for r in lie["reasons"])
    assert env.evidence_packs[-1]["type"] == "claim"


def test_claim_done_rejects_no_improvement():
    env = DesignSearchEnv(parent=HullState(), max_steps=5, seed=0)
    env.reset()
    v = env.claim_done()
    assert v["accepted"] is False
    assert "no_improvement_vs_parent" in v["reasons"]
    assert env.claim_done(require_improvement=False)["accepted"] is True


def test_claim_unknown_quantity_is_rejected():
    env = DesignSearchEnv(parent=HullState(), max_steps=5, seed=0)
    env.reset()
    v = env.claim_done({"Cd_L3": 0.1}, require_improvement=False)
    assert v["accepted"] is False
    assert "unmeasurable_claim:Cd_L3" in v["reasons"]
