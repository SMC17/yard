"""DesignSearchEnv45 — true 45-D Ship-D action space."""

from __future__ import annotations

import numpy as np

from yard_sea_v0.env45 import ACTION_DIM, DesignSearchEnv45, apply_shipd_delta
from yard_sea_v0.shipd import LABELS, load_action_bounds, action_scales
from yard_sea_v0.resistance_l1 import estimate_resistance


def test_env45_reset_exposes_shipd():
    env = DesignSearchEnv45(sample_index=0, max_steps=5, seed=1)
    obs, info = env.reset()
    assert len(info["shipd_vector"]) == 45
    assert info["shipd_labels"] == LABELS
    assert info["action_dim"] == ACTION_DIM
    assert obs.shape == (11,)
    assert info["shipd_feasible"] is True
    assert info["shipd_constraints"]["n"] == 49
    assert info["shipd_constraints"]["feasible"] is True
    assert env.action_space.shape == (ACTION_DIM,)


def test_env45_step_zeros_accepted():
    """Zero action: constraints stay feasible; L0-gated accept on sample 0."""
    env = DesignSearchEnv45(sample_index=0, max_steps=5, seed=2)
    env.reset()
    ct0 = estimate_resistance(env.state).Ct
    obs, reward, term, trunc, info = env.step(np.zeros(ACTION_DIM, dtype=np.float32))
    assert obs.shape == (11,)
    assert info.get("shipd_infeasible") is not True
    assert info["rejected"] is False
    assert abs(estimate_resistance(env.state).Ct - ct0) < 1e-12
    assert isinstance(reward, float)


def test_env45_infeasible_action_rejected():
    """Large push on Lb/Ls violates algebraic constraints → reject before L1."""
    env = DesignSearchEnv45(sample_index=0, max_steps=5, seed=3, delta_frac=0.5)
    env.reset()
    a = np.zeros(ACTION_DIM, dtype=np.float32)
    # Lb index 1, Ls index 2 — drive both toward upper band hard
    a[1] = 1.0
    a[2] = 1.0
    # Multiple steps if needed; first large step should often fail
    rejected_shipd = False
    for _ in range(8):
        _, reward, _, _, info = env.step(a)
        if info.get("shipd_infeasible"):
            rejected_shipd = True
            assert info["rejected"] is True
            assert reward < 0
            assert "shipd_algebraic_constraints" in info["monitor"]["reason_codes"]
            break
    assert rejected_shipd, "expected Ship-D algebraic rejection"


def test_env45_feasible_morph_l0_gated():
    """Small feasible morph: either improves Ct or stays accepted under L0."""
    env = DesignSearchEnv45(sample_index=0, max_steps=10, seed=4, delta_frac=0.05)
    env.reset()
    ct0 = estimate_resistance(env.state).Ct
    a = np.zeros(ACTION_DIM, dtype=np.float32)
    # WL index 6 — mild draft-fraction reduction tends to stay feasible on sample 0
    a[6] = -1.0
    _, reward, _, _, info = env.step(a)
    if info["rejected"]:
        # L0 or constraints may gate — still a valid monitor path
        assert info["monitor"]["allow"] is False
        assert reward < 0
    else:
        ct1 = info["ct"]
        assert info["shipd_infeasible"] is False
        # Accept: Ct should be finite; zero or improve is fine for one step
        assert np.isfinite(ct1)
        assert np.isfinite(reward)


def test_apply_shipd_delta_clamps_and_bits():
    lo, hi = load_action_bounds()
    scales = action_scales(lo, hi, delta_frac=0.05)
    v = np.asarray(DesignSearchEnv45(sample_index=0)._seed_vector.values, dtype=float)
    a = np.ones(45)
    out = apply_shipd_delta(v, a, lo=lo, hi=hi, scales=scales)
    assert out.shape == (45,)
    assert np.all(out >= lo - 1e-12)
    assert np.all(out <= hi + 1e-12)
    from yard_sea_v0.shipd import BIT_INDICES

    for i in BIT_INDICES:
        assert out[i] in (0.0, 1.0)
