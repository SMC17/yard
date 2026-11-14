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
    # HP every-step volumes may re-lerp with tiny float drift vs reset hull
    assert abs(estimate_resistance(env.state).Ct - ct0) < 1e-6
    assert info.get("geometry_source") == "hp"
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


def test_env45_hp_geometry_default_on():
    """use_hp_geometry defaults True when Ship-D vendor present."""
    env = DesignSearchEnv45(sample_index=0, max_steps=3, seed=10)
    _, info = env.reset()
    assert info["use_hp_geometry"] is True
    assert info["use_hp_hydro"] is True
    assert info["geometry_source"] == "hp"
    assert "hp_hydro" in info
    assert info["hp_hydro"]["primary"]["volume_m3"] > 0


def test_env45_hp_hydro_on_reset():
    """Explicit use_hp_geometry + every_n=0: HP on reset; steps stay project unless refresh."""
    env = DesignSearchEnv45(
        sample_index=0,
        max_steps=5,
        seed=11,
        use_hp_geometry=True,
        use_hp_hydro=True,
        hp_hydro_every_n=0,
    )
    _, info = env.reset()
    assert info["use_hp_hydro"] is True
    assert info["geometry_source"] == "hp"
    hydro = info["hp_hydro"]
    assert hydro["primary"]["volume_m3"] > 0
    assert hydro["primary"]["displacement_t"] > 0
    assert np.isfinite(hydro["primary"]["lcb_m"])
    assert np.isfinite(hydro["primary"]["vcb_m"])
    assert hydro["primary"]["awp_m2"] > 0
    # HullState refined from HP volumes on reset
    assert env.parent.volume() > 0
    # zero step without every_n should not reattach hp_hydro
    _, _, _, _, step_info = env.step(np.zeros(ACTION_DIM, dtype=np.float32))
    if not step_info["rejected"]:
        assert "hp_hydro" not in step_info


def test_env45_hp_geometry_can_disable():
    env = DesignSearchEnv45(
        sample_index=0,
        max_steps=3,
        seed=13,
        use_hp_geometry=False,
        use_hp_hydro=False,
    )
    _, info = env.reset()
    assert info["use_hp_geometry"] is False
    assert info["geometry_source"] == "project_fallback"
    assert "hp_hydro" not in info


def test_env45_hp_hydro_every_n():
    env = DesignSearchEnv45(
        sample_index=0,
        max_steps=6,
        seed=12,
        use_hp_geometry=True,
        use_hp_hydro=True,
        hp_hydro_every_n=2,
        delta_frac=0.02,
    )
    _, rinfo = env.reset()
    assert "hp_hydro" in rinfo
    # Zero actions stay feasible; steps 2 and 4 should refresh HP hydro.
    saw_even = saw_odd_without = False
    for _ in range(4):
        _, _, _, _, info = env.step(np.zeros(ACTION_DIM, dtype=np.float32))
        assert info.get("rejected") is False
        sc = env.step_count
        if sc % 2 == 0:
            assert "hp_hydro" in info
            assert info["hp_hydro"]["primary"]["volume_m3"] > 0
            saw_even = True
        else:
            assert "hp_hydro" not in info
            saw_odd_without = True
    assert saw_even and saw_odd_without


def test_env45_step_uses_hp_geometry_by_default():
    env = DesignSearchEnv45(sample_index=0, max_steps=4, seed=20, delta_frac=0.02)
    env.reset()
    _, _, _, _, info = env.step(np.zeros(ACTION_DIM, dtype=np.float32))
    if not info["rejected"]:
        assert info["geometry_source"] == "hp"
        assert "hp_hydro" in info
        assert info["hp_hydro"]["primary"]["volume_m3"] > 0
