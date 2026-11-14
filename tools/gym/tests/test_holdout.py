"""Held-out oracle check, surrogate-exploit flags, long-horizon drift."""

from __future__ import annotations

import numpy as np
import pytest

from yard_sea_v0.holdout import (
    holdout_check,
    make_holdout_fn,
    spearman,
    states_from_evidence,
    trajectory_drift,
)
from yard_sea_v0.hull import HullState
from yard_sea_v0.search import run_search


def test_spearman_basic():
    assert spearman([1, 2, 3, 4], [10, 20, 30, 40]) == pytest.approx(1.0)
    assert spearman([1, 2, 3, 4], [4, 3, 2, 1]) == pytest.approx(-1.0)
    assert spearman([1, 2], [1, 2]) is None


def test_exploit_flag_when_holdout_disagrees():
    parent = HullState()
    designs = [HullState(Cb=c) for c in (0.70, 0.72, 0.74)]
    seen = lambda d, p: 0.05  # cheap oracle claims every design improves  # noqa: E731
    hold = lambda d, p: {0.70: 0.04, 0.72: -0.03, 0.74: 0.01}[round(d.Cb, 2)]  # noqa: E731
    out = holdout_check(designs, parent, seen_fn=seen, holdout_fn=hold)
    assert out["n_claimed"] == 3
    assert out["n_exploit"] == 1 and out["rows"][1]["exploit"] is True
    assert out["n_confirmed"] == 2
    assert out["exploit_rate"] == pytest.approx(1 / 3)


def test_default_holdout_is_independent_oracle():
    parent = HullState()
    f = make_holdout_fn()
    assert f(parent, parent) == pytest.approx(0.0, abs=1e-12)
    out = holdout_check([HullState(Cb=0.7), HullState(Cb=0.8)], parent)
    assert out["holdout_oracle"] == "holdout_multi_froude_michell"
    assert all(isinstance(r["holdout"], float) for r in out["rows"])


def test_drift_grows_when_error_accumulates():
    parent = HullState()
    states = [HullState(Cb=0.75 - 0.01 * k) for k in range(6)]
    seen = lambda d, p: (0.75 - d.Cb) * 2.0  # noqa: E731
    hold = lambda d, p: (0.75 - d.Cb) * 1.0  # noqa: E731
    dr = trajectory_drift(states, parent, seen_fn=seen, holdout_fn=hold)
    assert dr["first_step_error"] == pytest.approx(0.0, abs=1e-12)
    assert dr["final_error"] == pytest.approx(0.05)
    assert dr["error_slope_per_step"] > 0


def test_run_search_holdout_is_post_hoc():
    base = run_search([HullState()], steps=8, seed=0)
    with_h = run_search([HullState()], steps=8, seed=0, holdout=True)
    for a, b in zip(base, with_h):
        assert a["reward_sum"] == b["reward_sum"]  # held-out oracle never touches the reward
        assert "holdout" in b and "drift" in b and "holdout" not in a
        assert b["drift"]["n_steps"] >= 1


def test_states_from_evidence_skips_claims_and_rejections():
    packs = [
        {"monitor": {"allow": True}, "hull": HullState().to_dict()},
        {"monitor": {"allow": False}, "hull": HullState().to_dict()},
        {"type": "claim", "hull": HullState().to_dict()},
    ]
    assert len(states_from_evidence(packs)) == 1


# --- selectable held-out oracles (michell / hm1984 / capytaine_l2) ---------------------------

import dataclasses  # noqa: E402

from yard_sea_v0 import zig_bridge  # noqa: E402
from yard_sea_v0.holdout import HOLDOUT_ORACLES, is_blind, seen_wave_model  # noqa: E402


def test_unknown_holdout_oracle_rejected():
    with pytest.raises(ValueError):
        make_holdout_fn(oracle="ittc")
    assert HOLDOUT_ORACLES == ("michell", "hm1984", "capytaine_l2")


def test_default_holdout_reports_independence_from_seen():
    parent = HullState()
    out = holdout_check([HullState(Cb=0.72)], parent)
    assert out["schema"] == "yard_sea_v0.holdout.v2"
    assert out["holdout_wave_model"] == "michell_l15"
    assert out["seen_wave_model"] == seen_wave_model(parent)
    assert out["independent_of_seen"] is True
    assert out["n_blind"] == 0 and out["holdout_available"] is True


@pytest.mark.skipif(not zig_bridge.zig_available(), reason="zig_gym not built")
def test_hm1984_holdout_is_not_independent_of_hm1984_seen():
    parent = HullState()
    f = make_holdout_fn(oracle="hm1984")
    assert f.available and f(parent, parent) == pytest.approx(0.0, abs=1e-12)
    out = holdout_check([HullState(Cb=0.72), HullState(B=21.0)], parent, holdout_fn=f)
    assert out["holdout_wave_model"] == "hm1984_zig"
    # Default L1 is HM1984 when zig_gym is built, so this oracle shares the seen wave model.
    assert seen_wave_model(parent) == "hm1984_zig"
    assert out["independent_of_seen"] is False
    assert all(isinstance(r["holdout"], float) and r["holdout"] == r["holdout"] for r in out["rows"])


def test_hm1984_holdout_unavailable_is_nan_not_fallback(monkeypatch):
    monkeypatch.setattr(zig_bridge, "zig_available", lambda *a, **k: False)
    f = make_holdout_fn(oracle="hm1984")
    out = holdout_check([HullState(Cb=0.72)], HullState(), holdout_fn=f)
    assert out["holdout_available"] is False and out["holdout_unavailable_reason"]
    r = out["rows"][0]
    assert r["holdout"] != r["holdout"]  # NaN: never silently replaced by the Python L1
    assert r["confirmed"] is False and r["exploit"] is False


def test_capytaine_holdout_is_blind_to_hull_form_coefficients():
    pytest.importorskip("capytaine")
    parent = HullState()
    f = make_holdout_fn(oracle="capytaine_l2")
    assert f.sensitive_to == ("L", "B", "T")
    cb_only = dataclasses.replace(parent, Cb=0.70, lcb_frac=0.01)
    wider = dataclasses.replace(parent, B=parent.B * 1.05)
    assert is_blind(f, cb_only, parent) and not is_blind(f, wider, parent)
    out = holdout_check([cb_only, wider], parent, holdout_fn=f)
    assert out["n_blind"] == 1 and out["rows"][0]["blind"] is True
    assert out["rows"][0]["holdout"] != out["rows"][0]["holdout"]  # NaN, not a fake 0
    h = out["rows"][1]["holdout"]
    assert h == h and h < 0  # wider box -> more radiation damping -> worse on this proxy
    assert out["independent_of_seen"] is True


@pytest.mark.skipif(not zig_bridge.zig_available(), reason="zig_gym not built")
def test_run_search_flags_shared_wave_model_as_not_held_out():
    rows = run_search([HullState()], steps=4, seed=0, holdout=True, holdout_oracle="hm1984")
    for r in rows:
        assert r["holdout"]["holdout_wave_model"] == "hm1984_zig"
        assert r["holdout"]["reward_wave_model"] == "hm1984_zig"
        assert r["holdout"]["independent_of_reward"] is False
    rows = run_search([HullState()], steps=4, seed=0, holdout=True)
    assert all(r["holdout"]["independent_of_reward"] is True for r in rows)


# --- long-horizon drift check (flag only) ----------------------------------------------------

import json  # noqa: E402

from yard_sea_v0.env import DesignSearchEnv  # noqa: E402
from yard_sea_v0.holdout import DEFAULT_DRIFT_THRESHOLD, long_horizon_drift_check  # noqa: E402


def _ramp(n):
    parent = HullState()
    states = [HullState(Cb=0.75 - 0.01 * k) for k in range(n)]
    seen = lambda d, p: (0.75 - d.Cb) * 4.0  # noqa: E731  cheap oracle over-claims, error grows
    hold = lambda d, p: (0.75 - d.Cb) * 1.0  # noqa: E731
    return states, parent, seen, hold


def test_drift_check_default_is_full_episode_and_documented_convention():
    states, parent, seen, hold = _ramp(8)
    c = long_horizon_drift_check(states, parent, seen_fn=seen, holdout_fn=hold)
    assert DEFAULT_DRIFT_THRESHOLD == 0.10
    assert c["horizon"] == 8 and c["horizon_requested"] is None
    assert c["threshold_source"] == "default_convention_not_validated"
    assert c["affects_reward"] is False and c["type"] == "drift_check"
    # error at step k = 3 * 0.01 * k -> 0.21 at k=7; first > 0.10 at k=4 (0.12)
    assert c["max_error"] == pytest.approx(0.21)
    assert c["exceeded"] is True and c["first_exceeding_step"] == 4


def test_drift_check_short_horizon_misses_late_drift():
    states, parent, seen, hold = _ramp(8)
    short = long_horizon_drift_check(states, parent, horizon=3, seen_fn=seen, holdout_fn=hold)
    assert short["horizon"] == 3 and short["exceeded"] is False  # why the default is the full episode
    loose = long_horizon_drift_check(states, parent, threshold=0.5, seen_fn=seen, holdout_fn=hold)
    assert loose["exceeded"] is False and loose["threshold_source"] == "user"


def test_drift_check_no_reference_and_bad_args():
    states, parent, seen, _ = _ramp(4)
    c = long_horizon_drift_check(states, parent, seen_fn=seen, holdout_fn=lambda d, p: float("nan"))
    assert c["exceeded"] is None and c["n_finite"] == 0
    with pytest.raises(ValueError):
        long_horizon_drift_check(states, parent, threshold=0.0)
    with pytest.raises(ValueError):
        long_horizon_drift_check(states, parent, horizon=0)


def test_record_evidence_does_not_touch_state_or_steps(tmp_path):
    env = DesignSearchEnv(parent=HullState(), max_steps=4, seed=0, evidence_dir=str(tmp_path))
    env.reset(seed=0)
    env.step(np.zeros(7, dtype=np.float32))
    before = (env.state, env.step_count, len(states_from_evidence(env.evidence_packs)))
    rec = env.record_evidence({"type": "drift_check", "exceeded": True})
    assert (env.state, env.step_count, len(states_from_evidence(env.evidence_packs))) == before
    on_disk = json.loads((tmp_path / f"{rec['evidence_id']}.json").read_text())
    assert on_disk["type"] == "drift_check" and on_disk["episode_id"] == env.episode_id


def test_run_search_records_drift_flag_without_changing_reward(tmp_path):
    base = run_search([HullState()], steps=6, seed=0)
    flagged = run_search(
        [HullState()], steps=6, seed=0, holdout=True, drift_threshold=1e-9, evidence_root=tmp_path
    )
    for a, b in zip(base, flagged):
        assert a["reward_sum"] == b["reward_sum"]
        lh = b["drift"]["long_horizon"]
        assert lh["threshold"] == 1e-9 and lh["threshold_source"] == "user"
        assert lh["exceeded"] in (True, None)
    recs = [json.loads(p.read_text()) for p in tmp_path.rglob("*.json")]
    checks = [r for r in recs if r.get("type") == "drift_check"]
    assert len(checks) == len(flagged) and all(c["affects_reward"] is False for c in checks)
    default = run_search([HullState()], steps=6, seed=0, holdout=True)
    assert all(r["drift"]["long_horizon"]["threshold"] == 0.10 for r in default)
