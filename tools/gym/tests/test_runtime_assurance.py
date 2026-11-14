"""Simplex-style runtime assurance: navigation (COLREG suite) and design-search wrappers."""

from __future__ import annotations

import numpy as np
import pytest

from yard_sea_v0.colreg_suite import generate, run_suite, simulate
from yard_sea_v0.env import DesignSearchEnv
from yard_sea_v0.faults import Fault, FaultInjector
from yard_sea_v0.hull import HullState
from yard_sea_v0.monitors import monitor_action
from yard_sea_v0.runtime_assurance import (
    LABEL,
    ColregRTA,
    CpaMonitor,
    DesignSimplex,
    FaultyObservation,
    HoldCoursePolicy,
    JitterPolicy,
    Simplex,
    Verdict,
)


def test_simplex_hysteresis_and_log():
    flags = iter([True, False, True, True, False, True, True, True])
    s = Simplex(lambda ctx, a: Verdict(next(flags)), recovery_steps=2)
    used = [s.decide(t, None, "adv", "fb")[0] for t in range(8)]
    assert used == ["adv", "fb", "fb", "adv", "fb", "fb", "adv", "adv"]
    summ = s.summary()
    assert summ["n_switches_to_fallback"] == 2 and summ["fallback_steps"] == 4
    assert summ["label"] == LABEL and "No formal guarantee" in summ["notes"]


def test_rta_rescues_hold_course_standin_in_head_on():
    sc = generate("head_on", 1, offset_range=(0.0, 0.0))
    bare = simulate(sc, HoldCoursePolicy())
    assert bare["collision"]
    rta = ColregRTA()
    wrapped = simulate(sc, HoldCoursePolicy(), wrapper=rta)
    assert not wrapped["collision"] and wrapped["passing_ok"]
    ra = wrapped["runtime_assurance"]
    assert ra["n_switches_to_fallback"] >= 1 and 0 < ra["fallback_fraction"] < 1
    assert ra["events"][0]["switch"] == "advanced->fallback"
    assert wrapped["returned_to_route"]


def test_rta_does_not_intervene_when_no_traffic_risk():
    sc = generate("head_on", 0)
    sc.targets = [t.__class__(t.x + 20000.0, t.y, t.course_deg, t.speed) for t in sc.targets]
    r = simulate(sc, HoldCoursePolicy(), wrapper=ColregRTA())
    assert r["runtime_assurance"]["n_switches_to_fallback"] == 0


def test_monitor_flags_port_turn_in_give_way():
    sc = generate("head_on", 0)
    v = CpaMonitor(horizon_s=5000.0)((sc.own, sc.targets, 0.0), 320.0)
    assert any("port_turn_in_head_on" in r for r in v.reasons)


def test_rta_cuts_collisions_for_untrusted_standins_across_suite():
    kinds = ("head_on", "crossing_starboard", "overtaking", "multi_ship")
    bare = run_suite(kinds, ("nominal",), range(4), policy_factory=HoldCoursePolicy)
    wrapped = run_suite(kinds, ("nominal",), range(4), policy_factory=HoldCoursePolicy,
                        wrapper_factory=ColregRTA)
    coll = lambda r: np.mean([x["collision"] for x in r["results"]])  # noqa: E731
    assert coll(bare) >= 0.5 and coll(wrapped) == 0.0
    jit = run_suite(kinds, ("nominal",), range(3), policy_factory=lambda: JitterPolicy(seed=3),
                    wrapper_factory=ColregRTA)
    assert all(x["runtime_assurance"]["steps"] > 0 for x in jit["results"])


def test_design_simplex_substitutes_feasible_action_and_logs_evidence():
    env = DesignSearchEnv(parent=HullState(lcb_frac=0.045), max_steps=5, seed=0)
    rta = DesignSimplex(env)
    rta.reset(seed=0)
    bad = np.array([0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0])  # LCB 0.045 → 0.055: outside L0 band
    assert not monitor_action(env.state, list(bad)).allow
    _, reward, _, _, info = rta.step(bad)
    assert info["rta"]["substituted"] and not info.get("rejected")
    assert reward != -1.0 and info["rta"]["fallback_scale"] == 0.5
    assert env.state.lcb_frac == pytest.approx(0.05)
    recs = [p for p in env.evidence_packs if p.get("type") == "rta_intervention"]
    assert recs and recs[0]["proposed_action"] == bad.tolist()
    # a safe action passes through untouched once recovered
    _, _, _, _, info2 = rta.step(np.zeros(7))
    assert info2["rta"]["substituted"] is False


def test_faulty_observation_bias_and_dropout_hold():
    env = DesignSearchEnv(parent=HullState(), max_steps=5, seed=0)
    inj = FaultInjector([Fault("bias", "obs", [10.0] + [0.0] * 10, 0.0, 1.5),
                         Fault("dropout", "obs", 0.0, 2.0, 3.0)])
    w = FaultyObservation(env, inj)
    o0, _ = w.reset(seed=0)
    assert o0[0] == pytest.approx(env._obs()[0] + 10.0)
    o1, *_ = w.step(np.zeros(7))  # step 1: bias still active
    o2, *_ = w.step(np.full(7, 0.2))  # step 2: dropped → stale hold of o1
    assert np.allclose(o2, o1)
    assert inj.summary()["n_dropped"] == 1
