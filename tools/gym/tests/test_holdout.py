"""Held-out oracle check, surrogate-exploit flags, long-horizon drift."""

from __future__ import annotations

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
