"""COLREG suite v1 (kinematics-only): generator, variants, baseline controller, metrics."""

from __future__ import annotations

import pytest

from yard_sea_v0.colreg_stub import classify, Thresholds
from yard_sea_v0.colreg_suite import (
    KINDS,
    LABEL,
    NOT_A_COMPLIANCE_CLAIM,
    VARIANTS,
    BaselineColregController,
    generate,
    run_suite,
    simulate,
)
from yard_sea_v0.faults import Fault, FaultInjector

SINGLE = [k for k in KINDS if k != "multi_ship"]


@pytest.mark.parametrize("kind", SINGLE)
@pytest.mark.parametrize("seed", [0, 1, 2, 3])
def test_generator_lands_in_requested_encounter(kind, seed):
    sc = generate(kind, seed)
    c = classify(sc.own, sc.targets[0], Thresholds(tcpa_max_s=1e9))
    assert c["encounter"] == kind and c["dcpa_m"] < Thresholds().dcpa_min_m


def test_generator_is_deterministic_and_multi_ship_has_several_targets():
    a, b = generate("multi_ship", 5), generate("multi_ship", 5)
    assert a.to_dict() == b.to_dict()
    assert len(a.targets) >= 2


@pytest.mark.parametrize("kind", ["head_on", "crossing_starboard", "overtaking", "multi_ship"])
def test_baseline_resolves_nominal_give_way_encounters(kind):
    for seed in range(5):
        r = simulate(generate(kind, seed))
        assert not r["collision"] and r["passing_ok"], r["scenario"]["id"]
        assert r["rule_consistent"], (r["scenario"]["id"], r["rule_checks"])
        assert r["time_to_resolve_s"] is not None and r["returned_to_route"]
        assert r["label"] == LABEL and r["notes"] == NOT_A_COMPLIANCE_CLAIM


def test_head_on_give_way_turns_starboard_readily_and_early():
    r = simulate(generate("head_on", 0))
    checks = r["rule_checks"]
    assert checks["t0_head_on_starboard"] and checks["t0_head_on_readily_apparent"] and checks["t0_head_on_early"]
    assert r["first_alteration"]["alteration_deg"] >= 30.0


def test_pure_stand_on_rule17_check():
    r = simulate(generate("crossing_port", 0))
    assert r["rule_checks"] == {"t0_crossing_port_stand_on_rule17": True}


def test_metrics_catch_port_turn_and_hold_course():
    sc = generate("head_on", 1, offset_range=(0.0, 0.0))
    port = simulate(sc, lambda t, o, ts, route: (route - 40.0) % 360.0)
    assert port["rule_checks"]["t0_head_on_starboard"] is False and not port["rule_consistent"]
    hold = simulate(sc, lambda t, o, ts, route: route)
    assert hold["collision"] and not hold["rule_checks"]["t0_head_on_took_action"]


def test_gnss_variant_corrupts_perception_not_truth():
    sc = generate("crossing_starboard", 0, "gnss_degraded")
    kinds = {f.kind for f in sc.faults}
    assert kinds == {"bias", "drift", "noise"}
    r = simulate(sc)
    assert r["faults"]["by_channel_kind"]["own_position:bias"] > 0
    # the same geometry without the fault is resolved cleanly
    clean = simulate(generate("crossing_starboard", 0, "nominal"))
    assert clean["passing_ok"]


def test_comms_loss_drops_target_tracks_and_manoeuvre_variant_applies_alteration():
    r = simulate(generate("head_on", 2, "comms_loss"))
    assert r["faults"]["n_dropped"] > 0
    sc = generate("crossing_starboard", 2, "comms_loss_manoeuvre")
    assert sc.manoeuvres and sc.manoeuvres[0][0] is not None
    simulate(sc)
    assert sc.manoeuvres[0][0] is not None  # scenario object not mutated by a run


def test_fault_injector_freeze_and_dropout():
    inj = FaultInjector([Fault("freeze", "x", 0.0, 10.0, 20.0), Fault("dropout", "y", 0.0, 0.0, 5.0)])
    assert list(inj.apply("x", 0.0, [1.0])) == [1.0]
    assert list(inj.apply("x", 12.0, [5.0])) == [1.0]  # stale value that looks valid
    assert list(inj.apply("x", 25.0, [7.0])) == [7.0]
    assert inj.apply("y", 1.0, [3.0]) is None
    s = inj.summary()
    assert s["n_dropped"] == 1 and s["by_channel_kind"]["x:freeze"] == 1


def test_suite_summary_covers_every_kind_and_variant():
    out = run_suite(seeds=(0,))
    assert out["n"] == len(KINDS) * len(VARIANTS)
    assert set(out["summary"]) == {f"{k}/{v}" for k in KINDS for v in VARIANTS}
    for row in out["summary"].values():
        assert 0.0 <= row["collision_rate"] <= 1.0
    nominal = [v for k, v in out["summary"].items() if k.endswith("/nominal")]
    assert all(v["collision_rate"] == 0.0 for v in nominal)


def test_controller_log_records_mode_changes():
    ctl = BaselineColregController()
    simulate(generate("head_on", 0), ctl)
    modes = [e["mode"] for e in ctl.log]
    assert modes[0] == "give_way" and modes[-1] == "transit"


def test_stand_on_rule17a_ii_acts_earlier_to_starboard_and_stays_rule_consistent():
    from yard_sea_v0.colreg_suite import BaselineColregController

    gains = []
    for seed in range(6):
        sc = generate("crossing_port", seed)
        new = simulate(sc, BaselineColregController())
        old = simulate(sc, BaselineColregController(rule17a=False))
        assert new["rule_consistent"] and not new["collision"]
        if new["controller_log"]:
            first = new["controller_log"][0]
            assert first["mode"] in ("stand_on_17a_ii", "last_resort") and first["alteration_deg"] > 0
            if old["controller_log"]:
                assert first["t"] <= old["controller_log"][0]["t"]
        gains.append(new["min_range_m"] - old["min_range_m"])
    assert sum(gains) > 0


def test_rule17a_ii_waits_for_grace_period():
    from yard_sea_v0.colreg_suite import BaselineColregController, SuiteConventions

    sc = generate("crossing_port", 1)
    c = BaselineColregController(conv=SuiteConventions(stand_on_grace_s=1e9))
    r = simulate(sc, c)
    assert all(e["mode"] != "stand_on_17a_ii" for e in r["controller_log"])
