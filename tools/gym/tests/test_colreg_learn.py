import math

import numpy as np
import pytest

from yard_sea_v0.colreg_learn import (
    N_FEAT, N_PARAMS, ColregGymEnv, MLPPolicy, cem_train, episode_cost, features, load_cem,
)
from yard_sea_v0.colreg_suite import generate, simulate
from yard_sea_v0.runtime_assurance import ColregRTA


def test_features_and_zero_policy_follow_route():
    sc = generate("head_on", 0)
    f = features(sc.own, sc.targets, 0.0)
    assert f.shape == (N_FEAT,) and np.all(np.isfinite(f)) and f[2] == 1.0
    assert features(sc.own, [], 0.0)[2:].sum() == 0.0
    assert MLPPolicy(np.zeros(N_PARAMS))(0.0, sc.own, sc.targets, 0.0) == pytest.approx(0.0)


def test_cem_smoke_improves_or_keeps_best():
    scs = [generate("crossing_starboard", 1000), generate("head_on", 1000)]
    res = cem_train(scs, iters=2, pop=6, seed=1)
    assert len(res["params"]) == N_PARAMS and res["history"][-1]["best"] <= res["history"][0]["median"]


def test_shipped_cem_policy_is_wrapped_safely_on_held_out_seeds():
    pol = load_cem()
    for kind in ("head_on", "crossing_starboard", "multi_ship"):
        sc = generate(kind, 7)
        r = simulate(sc, pol, wrapper=ColregRTA())
        assert not r["collision"] and math.isfinite(episode_cost(r))


def test_gym_env_episode_terminates_with_suite_result():
    env = ColregGymEnv([generate("head_on", 1000)], decision_s=60.0)
    obs, info = env.reset(seed=0)
    assert obs.shape == (N_FEAT,)
    total, done, n = 0.0, False, 0
    while not done:
        obs, r, done, trunc, info = env.step(np.array([0.3], dtype=np.float32))
        total += r
        n += 1
    assert "result" in info and info["result"]["label"] == "colreg_suite_v1" and n > 10


def test_ppo_smoke_if_available():
    pytest.importorskip("stable_baselines3")
    from yard_sea_v0.colreg_learn import SB3Policy, ppo_train

    m = ppo_train(512, n_envs=1)
    r = simulate(generate("head_on", 3), SB3Policy(m), wrapper=ColregRTA())
    assert r["runtime_assurance"]["steps"] > 0
