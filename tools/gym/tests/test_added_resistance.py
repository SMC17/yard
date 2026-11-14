import dataclasses
import math

import numpy as np
import pytest

from yard_sea_v0.added_resistance import (
    LABEL, crosscheck_capytaine, mean_added_resistance, raw_components, sea_state_score, validity,
)
from yard_sea_v0.env import DesignSearchEnv
from yard_sea_v0.hull import G, RHO_SW, HullState
from yard_sea_v0.seakeeping import SeaState


H = HullState()


def test_short_wave_reflection_limit_matches_formula():
    c = raw_components(H, [6.0])
    V = H.Fn * math.sqrt(G * H.L)
    f1 = 0.692 * (V / math.sqrt(H.T * G)) ** 0.769 + 1.81 * H.Cb**6.95
    assert c["reflection"][0] == pytest.approx(0.5 * RHO_SW * G * H.B * f1, rel=1e-3)
    assert c["motion"][0] < 1e-3 * c["reflection"][0]


def test_motion_peak_near_wbar_one_and_vanishes_at_zero_speed():
    w = np.linspace(0.1, 3.0, 2000)
    c = raw_components(H, w)
    wbar = math.sqrt(H.L / G) * 0.25 ** (1 / 3) / (1.17 * H.Fn**-0.143) * w
    assert abs(wbar[np.argmax(c["motion"])] - 1.0) < 0.02
    peak = c["motion"].max() / (4 * RHO_SW * G * H.B**2 / H.L)
    assert peak == pytest.approx(60.3 * H.Cb**1.34 * H.Fn**1.5 * math.exp(-3.5 * H.Fn), rel=1e-3)
    assert np.all(raw_components(H, w, 0.0)["motion"] == 0)
    assert np.all(np.isfinite(c["total"])) and np.all(c["total"] >= 0)


def test_spectral_mean_scales_with_hs_squared_and_trends():
    a = mean_added_resistance(H, SeaState(Hs=2.0, Tp=8.0))
    b = mean_added_resistance(H, SeaState(Hs=4.0, Tp=8.0))
    assert b["mean_raw_N"] == pytest.approx(4 * a["mean_raw_N"], rel=1e-9)
    assert a["spectral_coverage"] > 0.99 and a["validity"]["within"]
    assert mean_added_resistance(dataclasses.replace(H, Cb=0.85))["mean_raw_N"] > a["mean_raw_N"]
    assert mean_added_resistance(dataclasses.replace(H, Fn=0.28))["mean_raw_N"] > a["mean_raw_N"]


def test_validity_flags():
    assert not validity(dataclasses.replace(H, L=40.0))["within"]
    assert not validity(H, Fr=0.33)["within"]
    assert validity(H)["within"]


def test_sea_state_score_and_env_mode():
    s = sea_state_score(H, H)
    assert s["accepted"] and s["score"] == pytest.approx(0.0, abs=1e-12)
    out = sea_state_score(dataclasses.replace(H, L=40.0, B=6.7, T=2.7), H)
    assert not out["accepted"]
    env = DesignSearchEnv(parent=HullState(), max_steps=3, reward_mode="sea_state", seed=0)
    env.reset(seed=0)
    _, r, *_ , info = env.step(np.zeros(env.action_space.shape, dtype=np.float32))
    assert np.isfinite(r)
    assert env.evidence_packs[-1]["sea_state"]["label"] == LABEL
    assert env.candidate_reward(env.state) == pytest.approx(r)
    assert "sea_state_score" in env.claim_done(require_improvement=False)["measured"]


def test_crosscheck_capytaine_if_available():
    pytest.importorskip("capytaine")
    x = crosscheck_capytaine(H)
    assert x["available"]
    # Forward-speed regression vs zero-speed potential flow: same order, STAwave-2 larger.
    assert 1.0 < x["ratio_stawave_design_over_capytaine0"] < 10.0
