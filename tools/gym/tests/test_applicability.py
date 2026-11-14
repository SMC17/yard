"""Applicability (declared range + tank-validated envelope) and empirical drift defaults."""

import dataclasses

from yard_sea_v0.acceptance import accept_l1
from yard_sea_v0.applicability import assess, canonical_oracle
from yard_sea_v0.evidence import build_evidence
from yard_sea_v0.holdout import (
    DEFAULT_DRIFT_THRESHOLD,
    long_horizon_drift_check,
    make_holdout_fn,
    resolve_drift_threshold,
    seen_improvement,
)
from yard_sea_v0.hull import HullState, evaluate_l0
from yard_sea_v0.resistance_l1 import estimate_resistance

KCS_FULL = HullState(L=230.0, B=32.2, T=10.8, Cb=0.6505, lcb_frac=-0.0148, Fn=0.152)


def test_aliases_map_fidelity_tags_to_report_names():
    assert canonical_oracle("hm1984_zig") == "hm1984_gym"
    assert canonical_oracle("simplified_py") == "simplified_py"
    assert canonical_oracle("michell") == "michell_l15"
    assert canonical_oracle("capytaine_l2_box") is None


def test_kcs_like_hull_at_validated_speed_is_inside_envelope():
    ap = assess(KCS_FULL, "hm1984_zig")
    assert ap["in_declared_range"] is True
    assert ap["in_validated_envelope"] is True, ap["envelope_violations"]
    assert ap["affects_reward"] is False and ap["reynolds_extrapolated"] is True


def test_nearest_failed_reference_flags_even_inside_box():
    # HM1984 (no bulb term) over-predicts KCS by ~18% at Fn 0.26
    ap = assess(dataclasses.replace(KCS_FULL, Fn=0.26), "hm1984_zig")
    assert ap["in_validated_envelope"] is False
    assert any("nearest reference KCS@Fn=0.260 failed" in v for v in ap["envelope_violations"])


def test_slender_box_hull_outside_envelope_and_declared_range():
    h = HullState(L=200.0, B=14.0, T=6.0, Cb=0.5, Fn=0.3)  # L/B 14.3, Cp 0.51
    ap = assess(h, "hm1984_zig")
    assert ap["in_declared_range"] is False and any(v.startswith("Cp=") for v in ap["declared_violations"])
    assert ap["in_validated_envelope"] is False


def test_unvalidated_oracle_is_reported_not_guessed():
    ap = assess(HullState(), "capytaine_l2_box")
    assert ap["in_validated_envelope"] is None and ap["validation_status"] == "unvalidated"


def test_advisory_checks_never_change_acceptance_verdict():
    h = HullState()
    r = estimate_resistance(h)
    plain, adv = accept_l1(r), accept_l1(r, hull=h)
    assert plain.passed == adv.passed is True
    d = adv.to_dict()
    assert "in_tank_validated_envelope" in d["failed_advisories"]
    assert d["failed_checks"] == []


def test_evidence_records_applicability_and_flags_claim():
    h = HullState()
    pack = build_evidence(hull=h, l0=evaluate_l0(h), resistance=estimate_resistance(h), seed=0, step=0,
                          episode_id="t", reward=0.0, action=None, monitor_allowed=True, monitor_reasons=[])
    assert pack["applicability"]["in_validated_envelope"] is False
    ids = [c["id"] for c in pack["claims"]]
    assert "outside_validated_envelope" in ids and "drag_rank_l1" in ids


def test_drift_default_is_empirical_for_validated_pair_and_fallback_otherwise():
    p = HullState()
    mich = resolve_drift_threshold(seen_improvement, make_holdout_fn(oracle="michell"), p)
    assert mich["source"] == "empirical_tank_validation" and 0.05 < mich["threshold"] < 0.5
    assert mich["derivation"]["n_pairs"] >= 20
    capy = resolve_drift_threshold(seen_improvement, make_holdout_fn(oracle="capytaine_l2"), p)
    assert capy["source"] == "default_convention_not_validated" and capy["threshold"] == DEFAULT_DRIFT_THRESHOLD


def test_long_horizon_check_records_empirical_threshold_and_derivation():
    p = HullState()
    states = [dataclasses.replace(p, Cb=p.Cb - 0.01 * i) for i in range(1, 4)]
    c = long_horizon_drift_check(states, p, holdout_fn=make_holdout_fn(oracle="michell"))
    assert c["threshold_source"] == "empirical_tank_validation"
    assert c["threshold_derivation"]["quantile"] == 0.95
    u = long_horizon_drift_check(states, p, threshold=0.2, holdout_fn=make_holdout_fn(oracle="michell"))
    assert u["threshold_source"] == "user" and u["threshold_derivation"] is None


def test_michell_record_carries_real_lines_result():
    from yard_sea_v0.applicability import assess, load_report

    rep = load_report()
    if not rep or "michell_lines" not in rep["per_oracle"]:
        pytest.skip("report without michell_lines")
    a = assess(HullState(), "michell")
    rl = a["validation"]["real_hull_lines"]
    assert rl["oracle"] == "michell_lines" and rl["mean_abs_E_pct"] > 20
