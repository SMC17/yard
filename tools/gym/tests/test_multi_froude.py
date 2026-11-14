"""Multi-Froude reward: friction/pressure split, worst-case penalty, acceptance per Fn."""

from __future__ import annotations

import numpy as np
import pytest

from yard_sea_v0.env import DesignSearchEnv
from yard_sea_v0.hull import HullState, evaluate_l0
from yard_sea_v0.multi_froude import evaluate_point, fn_grid_for, multi_froude_score
from yard_sea_v0.resistance_l1 import estimate_resistance


def test_point_decomposition_sums_to_l1_ct():
    h = HullState()
    pt = evaluate_point(h, 0.2)
    assert pt.accepted
    assert pt.total == pytest.approx(estimate_resistance(h).Ct, rel=1e-12)
    assert pt.pressure == pytest.approx(pt.viscous_pressure + pt.wave)


def test_terms_partition_total_improvement():
    parent, child = HullState(), HullState(Cb=0.68)
    out = multi_froude_score(child, parent, [0.17, 0.2, 0.25])
    for r in out["points"]:
        d_allow = (r["parent"]["allowance"] - r["child"]["allowance"]) / r["parent"]["total"]
        assert r["d_friction"] + r["d_pressure"] + d_allow == pytest.approx(r["d_total"], abs=1e-12)
    assert out["accepted"] and out["n_credited"] == 3


def test_identical_hull_scores_zero():
    out = multi_froude_score(HullState(), HullState())
    assert out["score"] == pytest.approx(0.0, abs=1e-12)
    assert out["fn_grid"] == list(fn_grid_for(HullState()))


def test_out_of_envelope_fn_not_credited():
    out = multi_froude_score(HullState(Cb=0.7), HullState(), [0.2, 0.5])
    assert out["accepted"] is False
    assert out["n_credited"] == 1
    assert out["points"][1]["credited"] is False


def test_off_design_penalty_catches_point_optimised_hull():
    """A hull that edges the parent at design Fn but loses off-design must score below zero.

    Composite oracle (L1 viscous + L1.5 Michell wave). The magnitude here (~3%) is far
    smaller than published KCS RANS results; this checks the mechanism, not the physics.
    """
    parent = HullState(Fn=0.195)
    child = HullState(L=130.0, B=24.0, T=10.0, Cb=0.65, Fn=0.195)
    assert evaluate_l0(child).feasible
    single = multi_froude_score(child, parent, [0.195], wave_oracle="michell")
    assert single["score"] > 0  # single-Fn scoring would credit it
    multi = multi_froude_score(child, parent, [0.195, 0.25], wave_oracle="michell")
    by_fn = {r["Fn"]: r for r in multi["points"]}
    assert by_fn[0.25]["d_total"] < -0.02
    assert multi["worst_Fn"] == 0.25
    assert multi["score"] < 0


def test_env_multi_froude_mode_reports_breakdown():
    env = DesignSearchEnv(parent=HullState(), max_steps=3, seed=0, reward_mode="multi_froude")
    env.reset()
    a = np.zeros(7, dtype=np.float32)
    a[3] = -0.2
    _, reward, _, _, info = env.step(a)
    mf = info["multi_froude"]
    assert mf["accepted"] and len(mf["points"]) == 3
    assert {"mean_d_friction", "mean_d_pressure", "worst_d_total"} <= set(mf)
    assert np.isfinite(reward)
    assert env.evidence_packs[-1]["multi_froude"]["fn_grid"] == mf["fn_grid"]


def test_env_rejects_unknown_mode():
    with pytest.raises(ValueError):
        DesignSearchEnv(reward_mode="nope")


def test_hillclimb_optimises_env_objective_in_multi_froude_mode():
    from yard_sea_v0.search import run_search

    rows = run_search([HullState()], steps=6, seed=0, reward_mode="multi_froude")
    hill = [r for r in rows if r["method"] == "hillclimb"][0]
    assert hill["reward_sum"] > -6.0  # not all rejected
    assert "claim" in hill


def test_claim_in_multi_froude_mode_requires_grid_improvement():
    parent = HullState(Fn=0.195)
    env = DesignSearchEnv(parent=parent, seed=0, reward_mode="multi_froude",
                          fn_grid=(0.195, 0.25), wave_oracle="michell")
    env.reset()
    env.state = HullState(L=130.0, B=24.0, T=10.0, Cb=0.65, Fn=0.195)  # point-optimised hull
    v = env.claim_done()
    assert v["accepted"] is False
    assert "no_improvement_vs_parent" in v["reasons"]
    assert v["multi_froude"]["worst_Fn"] == 0.25


# --- wave_oracle="auto" resolution -------------------------------------------------

from yard_sea_v0 import resistance_l1 as _r1
from yard_sea_v0.multi_froude import resolve_wave_oracle


def test_auto_prefers_michell_when_l1_is_damped(monkeypatch):
    real = _r1.estimate_resistance
    monkeypatch.setattr(
        "yard_sea_v0.multi_froude.estimate_resistance",
        lambda h, **kw: real(h, prefer_zig_hm1984=False),
    )
    w = resolve_wave_oracle("auto", HullState())
    assert w["l1_fidelity"] == "simplified_py"
    assert w["resolved"] == "michell"
    assert w["wave_term_damped"] is False


def test_auto_keeps_l1_when_hm1984(monkeypatch):
    class _R:
        fidelity = "hm1984_zig"

    monkeypatch.setattr("yard_sea_v0.multi_froude.estimate_resistance", lambda h, **kw: _R())
    w = resolve_wave_oracle("auto", HullState())
    assert w["resolved"] == "l1" and w["reason"] == "l1_is_hm1984_zig"


def test_explicit_damped_l1_is_flagged(monkeypatch):
    real = _r1.estimate_resistance
    monkeypatch.setattr(
        "yard_sea_v0.multi_froude.estimate_resistance",
        lambda h, **kw: real(h, prefer_zig_hm1984=False),
    )
    w = resolve_wave_oracle("l1", HullState())
    assert w["resolved"] == "l1" and w["wave_term_damped"] is True


def test_score_records_resolution():
    parent = HullState()
    child = HullState(L=112.0, Cb=0.8)
    out = multi_froude_score(child, parent)
    assert out["wave_resolution"]["requested"] == "auto"
    assert out["wave_oracle"] == out["wave_resolution"]["resolved"]


def test_bad_wave_oracle_rejected():
    with pytest.raises(ValueError):
        resolve_wave_oracle("bogus", HullState())
