from yard_sea_v0.colreg_suite import generate, run_suite, simulate
from yard_sea_v0.runtime_assurance import HoldCoursePolicy


def test_default_targets_are_scripted():
    out = simulate(generate("crossing_port", 0))
    assert out["target_behaviour"] == "scripted" and out["target_logs"] is None


def test_give_way_target_alters_to_starboard_and_own_stands_on():
    sc = generate("crossing_port", 1)
    out = simulate(sc, reciprocal=True)
    tlog = out["target_logs"][0]
    assert tlog and tlog[0]["mode"] == "give_way" and tlog[0]["alteration_deg"] > 0
    assert out["controller_log"] == [] and not out["collision"] and out["passing_ok"]


def test_head_on_both_turn_starboard():
    out = simulate(generate("head_on", 2), reciprocal=True)
    assert out["controller_log"][0]["alteration_deg"] > 0
    assert out["target_logs"][0][0]["mode"] == "give_way" and out["target_logs"][0][0]["alteration_deg"] > 0
    assert not out["collision"]


def test_reciprocal_targets_rescue_a_non_manoeuvring_own_ship_mostly():
    kinds = ("head_on", "crossing_starboard", "crossing_port", "overtaken")
    bare = run_suite(kinds, ("nominal",), range(4), policy_factory=HoldCoursePolicy)
    rec = run_suite(kinds, ("nominal",), range(4), policy_factory=HoldCoursePolicy, reciprocal=True)
    c = lambda r: sum(x["collision"] for x in r["results"])  # noqa: E731
    assert rec["reciprocal"] and c(rec) < c(bare)
    # own ship still breaks the rules when it is the give-way vessel and holds course
    assert not all(x["rule_consistent"] for x in rec["results"])
