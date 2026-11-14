"""Fidelity choice as an agent action: explicit cost, LF-mistrust fallback to HF."""

from __future__ import annotations

import numpy as np
import pytest

from yard_sea_v0.fidelity import (
    FidelityChoiceEnv,
    FidelityLevel,
    MistrustMonitor,
    default_ladder,
)
from yard_sea_v0.hull import HullState

MORPH = np.zeros(7)
MORPH[3] = -0.2  # small Cb reduction: L0-feasible, L1-accepted on the default hull
LF, HF = -1.0, 1.0


def _act(sel: float) -> np.ndarray:
    return np.concatenate([MORPH, [sel]]).astype(np.float32)


def _ladder(lf_fn, hf_fn, lf_cost=1.0, hf_cost=10.0):
    return [FidelityLevel("lf", lf_cost, lf_fn), FidelityLevel("hf", hf_cost, hf_fn)]


def test_monitor_reasons():
    m = MistrustMonitor(min_pairs=2, max_abs_err=0.01)
    assert m.mistrust(0.1) == "cold_start"
    m.add_pair(0.10, 0.10)
    m.add_pair(0.05, 0.05)
    assert m.mistrust(0.08) is None
    assert m.mistrust(0.5) == "extrapolation"
    m.add_pair(0.05, -0.20)
    assert m.mistrust(0.05) in ("lf_hf_error", "sign_disagreement")
    assert MistrustMonitor().mistrust(None) == "lf_not_credited"


def test_cold_start_forces_hf_and_charges_it():
    env = FidelityChoiceEnv(ladder=_ladder(lambda c, p: 0.5, lambda c, p: 0.1), max_steps=5)
    env.reset(seed=0)
    _, r, _, _, info = env.step(_act(LF))
    rec = info["fidelity_choice"]
    assert rec["requested"] == "lf" and rec["used"] == "hf"
    assert rec["forced_hf"] == "cold_start"
    assert rec["cost_charged"] == 11.0
    assert rec["value_used"] == pytest.approx(0.1)


def test_trusted_lf_is_used_after_calibration():
    env = FidelityChoiceEnv(
        ladder=_ladder(lambda c, p: 0.10, lambda c, p: 0.101),
        monitor=MistrustMonitor(min_pairs=2, max_abs_err=0.01),
        max_steps=10,
    )
    env.reset(seed=0)
    for _ in range(2):
        env.step(_act(HF))  # HF steps also run LF -> calibration pairs
    _, _, _, _, info = env.step(_act(LF))
    rec = info["fidelity_choice"]
    assert rec["used"] == "lf" and rec["forced_hf"] is None and rec["cost_charged"] == 1.0


def test_lying_lf_stays_mistrusted():
    # LF says every move is great; HF says it is worse. The agent cannot ride LF.
    env = FidelityChoiceEnv(
        ladder=_ladder(lambda c, p: 0.3, lambda c, p: -0.05),
        monitor=MistrustMonitor(min_pairs=2),
        max_steps=8,
    )
    env.reset(seed=0)
    used = []
    for _ in range(6):
        _, r, _, _, info = env.step(_act(LF))
        used.append(info["fidelity_choice"]["used"])
    assert used == ["hf"] * 6
    s = env.summary()
    assert s["n_forced_hf"] == 6
    assert set(s["forced_reasons"]) <= {"cold_start", "lf_hf_error", "sign_disagreement"}


def test_cost_budget_truncates():
    env = FidelityChoiceEnv(ladder=_ladder(lambda c, p: 0.1, lambda c, p: 0.1), cost_budget=25.0, max_steps=50)
    env.reset(seed=0)
    truncated, n = False, 0
    while not truncated:
        _, _, _, truncated, _ = env.step(_act(HF))
        n += 1
    assert n == 3 and env.cost_spent >= 25.0


def test_claim_requires_hf_improvement():
    env = FidelityChoiceEnv(ladder=_ladder(lambda c, p: 0.2, lambda c, p: -0.01), max_steps=5)
    env.reset(seed=0)
    env.step(_act(HF))
    v = env.claim_done(require_improvement=False)
    assert v["accepted"] is True  # not requiring improvement
    v = env.claim_done()
    assert any(r.startswith("no_improvement_at_hf") for r in v["reasons"])
    assert v["accepted"] is False
    assert v["hf_measured"]["level"] == "hf"


def test_evidence_pack_carries_fidelity(tmp_path):
    import json

    env = FidelityChoiceEnv(
        ladder=_ladder(lambda c, p: 0.1, lambda c, p: 0.1), evidence_dir=str(tmp_path), max_steps=3
    )
    env.reset(seed=0)
    env.step(_act(LF))
    files = list(tmp_path.glob("*.json"))
    assert len(files) == 1
    pack = json.loads(files[0].read_text())
    assert pack["fidelity_choice"]["requested"] == "lf"
    assert pack["fidelity_choice"]["forced_hf"] == "cold_start"


def test_real_ladder_episode():
    env = FidelityChoiceEnv(ladder=default_ladder(), max_steps=6, cost_budget=500)
    obs, info = env.reset(seed=3)
    assert obs.shape == (13,)
    assert [lv["name"] for lv in info["fidelity_ladder"]] == ["L1", "L1.5"]
    rng = np.random.default_rng(0)
    for _ in range(6):
        a = np.concatenate([rng.uniform(-0.3, 0.3, 7), [LF]])
        obs, r, term, trunc, info = env.step(a)
        assert np.isfinite(r)
        if trunc:
            break
    s = env.summary()
    assert s["requested"]["L1"] == s["n_steps"]
    # Real L1 vs multi-Froude Michell is not interchangeable early on: HF is forced.
    assert s["n_forced_hf"] >= 1
    assert s["cost_spent"] > s["n_steps"]
