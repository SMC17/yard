from yard_sea_v0.env45 import DesignSearchEnv45
from yard_sea_v0.shipd import LABELS


def test_env45_reset_exposes_shipd():
    env = DesignSearchEnv45(sample_index=0, max_steps=5, seed=1)
    obs, info = env.reset()
    assert len(info["shipd_vector"]) == 45
    assert info["shipd_labels"] == LABELS
    assert obs.shape == (11,)
