"""COLREG scenario stub: geometry-only encounter roles + simplified manoeuvre checks."""

from __future__ import annotations

import math

import pytest

from yard_sea_v0.colreg_stub import (
    LABEL,
    NOT_A_COMPLIANCE_CLAIM,
    Thresholds,
    Vessel,
    classify,
    collision_course_targets,
    cpa_tcpa,
    evaluate_manoeuvre,
    relative_bearing,
    scenario_suite,
)

OWN = Vessel(0.0, 0.0, 0.0, 6.0)  # at origin, heading north, ~11.7 kn


def test_cpa_tcpa_closed_form():
    # Reciprocal courses offset 500 m east: CPA 500 m when abeam, after 2000 m / 12 m/s.
    d, t = cpa_tcpa(OWN, Vessel(500.0, 2000.0, 180.0, 6.0))
    assert d == pytest.approx(500.0) and t == pytest.approx(2000.0 / 12.0)
    d, t = cpa_tcpa(OWN, Vessel(0.0, 100.0, 0.0, 6.0))  # same velocity: never closes
    assert d == pytest.approx(100.0) and t == 0.0


def test_relative_bearing_convention():
    assert relative_bearing(OWN, Vessel(1000.0, 0.0, 0.0, 0.0)) == pytest.approx(90.0)  # starboard beam
    assert relative_bearing(OWN, Vessel(-1000.0, 0.0, 0.0, 0.0)) == pytest.approx(270.0)


@pytest.mark.parametrize("brg,ratio", [(0, 1.0), (30, 1.0), (60, 1.5), (300, 1.0), (330, 1.5)])
def test_collision_course_targets_have_zero_cpa(brg, ratio):
    tgts = collision_course_targets(OWN, 3704.0, brg, 6.0 * ratio)
    assert tgts
    for t in tgts:
        d, tc = cpa_tcpa(OWN, t)
        assert d == pytest.approx(0.0, abs=1e-6) and tc > 0


@pytest.mark.parametrize(
    "brg,ratio,enc,role",
    [
        (0, 1.0, "head_on", "give_way"),
        (30, 1.0, "crossing_starboard", "give_way"),
        (90, 1.5, "crossing_starboard", "give_way"),
        (270, 1.5, "crossing_port", "stand_on"),
        (330, 1.0, "crossing_port", "stand_on"),
    ],
)
def test_roles_on_canonical_encounters(brg, ratio, enc, role):
    tgt = collision_course_targets(OWN, 3704.0, brg, 6.0 * ratio)[0]
    c = classify(OWN, tgt)
    assert (c["encounter"], c["role"], c["risk_of_collision"]) == (enc, role, True)
    assert c["label"] == LABEL and c["notes"] == NOT_A_COMPLIANCE_CLAIM


def test_overtaking_and_overtaken_roles_and_lookahead():
    slow_ahead = Vessel(0.0, 1500.0, 0.0, 3.0)
    assert classify(OWN, slow_ahead)["encounter"] == "overtaking"
    assert classify(OWN, slow_ahead)["role"] == "give_way"  # Rule 13: overtaking vessel keeps clear
    fast_astern = Vessel(0.0, -1500.0, 0.0, 9.0)
    c = classify(OWN, fast_astern)
    assert (c["encounter"], c["role"]) == ("overtaken", "stand_on")
    # Same geometry beyond the look-ahead horizon carries no role.
    far = classify(OWN, slow_ahead, Thresholds(tcpa_max_s=100.0))
    assert far["encounter"] == "overtaking" and far["role"] == "none"


def test_opening_or_distant_traffic_has_no_role():
    c = classify(OWN, Vessel(5000.0, 0.0, 90.0, 6.0))  # on starboard beam, heading away
    assert c["risk_of_collision"] is False and c["role"] == "none"


def test_give_way_starboard_crossing_manoeuvre_checks():
    tgt = collision_course_targets(OWN, 3704.0, 60.0, 6.0)[0]
    good = evaluate_manoeuvre(OWN, tgt, 40.0)
    assert good["passed"] is True and good["dcpa_after_m"] >= Thresholds().dcpa_min_m
    port = evaluate_manoeuvre(OWN, tgt, -40.0)
    assert port["checks"]["starboard_alteration"] is False
    assert port["checks"]["not_crossing_ahead"] is False  # turning to port crosses the target's bow
    small = evaluate_manoeuvre(OWN, tgt, 10.0)
    assert small["checks"]["readily_apparent"] is False and small["checks"]["passing_distance"] is False


def test_head_on_requires_starboard_and_stand_on_keeps_course():
    ho = collision_course_targets(OWN, 3704.0, 0.0, 6.0)[0]
    assert evaluate_manoeuvre(OWN, ho, 35.0)["passed"] is True
    assert evaluate_manoeuvre(OWN, ho, -35.0)["passed"] is False
    port_x = collision_course_targets(OWN, 3704.0, 300.0, 6.0)[0]
    assert evaluate_manoeuvre(OWN, port_x, 0.0)["passed"] is True
    assert evaluate_manoeuvre(OWN, port_x, 30.0)["checks"] == {"kept_course": False}


def test_scenario_suite_is_deterministic_and_covers_roles():
    a, b = scenario_suite(), scenario_suite()
    assert [s["id"] for s in a] == [s["id"] for s in b]
    encs = {s["encounter"] for s in a}
    assert {"head_on", "crossing_starboard", "crossing_port", "overtaking", "overtaken"} <= encs
    assert all(s["dcpa_m"] < 1e-6 for s in a)
    assert all(math.isfinite(s["tcpa_s"]) for s in a)
