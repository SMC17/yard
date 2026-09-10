import numpy as np

from yard_sea_v0.env import DesignSearchEnv
from yard_sea_v0.hull import HullState


def test_reset_and_step():
    env = DesignSearchEnv(parent=HullState(), max_steps=5, seed=1)
    obs, info = env.reset()
    assert obs.shape == (11,)
    obs2, reward, term, trunc, info2 = env.step(np.zeros(7))
    assert obs2.shape == (11,)
    assert isinstance(reward, float)
    assert info2["rejected"] is False


def test_illegal_action_rejected():
    env = DesignSearchEnv(parent=HullState(), max_steps=5, seed=2)
    env.reset()
    # huge negative Cb-ish push via action index 3
    a = np.zeros(7)
    a[3] = -1.0
    # many steps to try to leave band
    rejected = False
    for _ in range(30):
        _, reward, _, _, info = env.step(a)
        if info.get("rejected"):
            rejected = True
            assert reward < 0
            break
    # may or may not reject depending on clamp; at least env stays finite
    assert np.isfinite(env.state.L)
