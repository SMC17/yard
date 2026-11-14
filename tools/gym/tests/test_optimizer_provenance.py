"""BoTorch / multi-fidelity paths carry optimizer provenance and measured claims."""

from __future__ import annotations

import json

import pytest

from yard_sea_v0.hull import HullState
from yard_sea_v0.provenance import OptimizerRecord, load_episode_log, verify_log
from yard_sea_v0.resistance_l1 import estimate_resistance
from yard_sea_v0.search import botorch_available, finalize_optimizer_row


def _row_for(h: HullState, *, ct: float | None = None, improved: bool = True) -> dict:
    return {
        "method": "fake_opt",
        "ct": estimate_resistance(h).Ct if ct is None else ct,
        "hull": h.to_dict(),
        "improved": improved,
        "skipped": False,
    }


def test_finalize_measures_instead_of_trusting_optimizer(tmp_path):
    parent = HullState()
    opt = OptimizerRecord(implementation="fake", max_evals=3).start()
    for _ in range(3):
        opt.tick()
    # Optimizer reports "improved" for the parent itself: the measured claim must refuse it.
    row = finalize_optimizer_row(_row_for(parent, improved=True), parent, opt, seed=1, evidence_dir=tmp_path)
    assert row["optimizer_claimed_improved"] is True
    assert row["improved"] is False
    assert "no_improvement_vs_parent" in row["claim"]["reasons"]
    assert row["optimizer"]["used"]["evals"] == 3
    assert row["optimizer"]["budget"]["max_evals"] == 3
    assert row["seeds"]["base_seed"] == 1
    assert row["evidence_count"] >= 1
    log = load_episode_log(row["evidence_log"]["path"])
    assert verify_log(row["evidence_log"]["path"])
    assert log["records"][-1]["type"] == "claim"
    assert log["records"][-1]["optimizer"]["implementation"] == "fake"


def test_finalize_rejects_misreported_ct():
    parent = HullState()
    child = HullState(L=parent.L * 1.05, B=parent.B, T=parent.T, Cb=parent.Cb * 0.97,
                      lcb_frac=parent.lcb_frac, kg_frac=parent.kg_frac, Fn=parent.Fn)
    true_ct = estimate_resistance(child).Ct
    opt = OptimizerRecord(implementation="fake", max_evals=1).start()
    row = finalize_optimizer_row(_row_for(child, ct=true_ct * 0.5), parent, opt, seed=0)
    assert row["improved"] is False
    assert any(r.startswith("claim_mismatch") for r in row["claim"]["reasons"])


def test_finalize_skipped_row_still_gets_optimizer():
    opt = OptimizerRecord(implementation="fake")
    row = finalize_optimizer_row({"method": "x", "skipped": True}, HullState(), opt, seed=0)
    assert row["optimizer"]["implementation"] == "fake"
    assert "claim" not in row


@pytest.mark.skipif(not botorch_available(), reason="botorch/torch not installed")
def test_botorch_child_records_optimizer_and_claim(tmp_path):
    from yard_sea_v0.search import _botorch_child

    row = _botorch_child(HullState(), steps=3, seed=5, evidence_dir=tmp_path)
    assert row is not None and not row.get("skipped")
    o = row["optimizer"]
    assert o["implementation"].startswith("botorch.")
    assert "botorch" in json.loads(o["version"])
    assert o["budget"]["max_evals"] == o["settings"]["n_init"] + o["settings"]["n_bo_steps"]
    assert o["used"]["evals"] == o["budget"]["max_evals"]
    assert o["used"]["wall_s"] > 0
    assert row["claim"]["measured_ct"] == pytest.approx(row["ct"], rel=1e-9)
    assert row["improved"] == row["claim"]["accepted"]
    assert verify_log(row["evidence_log"]["path"])


@pytest.mark.skipif(not botorch_available(), reason="botorch/torch not installed")
def test_mf_cost_aware_records_optimizer(tmp_path):
    from yard_sea_v0.multifidelity import _botorch_stage_a_cost_aware

    row = _botorch_stage_a_cost_aware(HullState(), steps=3, seed=9, evidence_dir=tmp_path)
    assert row is not None and not row.get("skipped")
    o = row["optimizer"]
    assert "qLogExpectedImprovement" in o["implementation"]
    assert "cost_utility_applied" in o["settings"]
    assert o["used"]["evals"] == o["budget"]["max_evals"]
    assert "claim" in row and row["improved"] == row["claim"]["accepted"]
