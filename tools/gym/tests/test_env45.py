from yard_sea_v0.env45 import DesignSearchEnv45
from yard_sea_v0.shipd import LABELS


def test_env45_reset_exposes_shipd():
    env = DesignSearchEnv45(sample_index=0, max_steps=5, seed=1)
    obs, info = env.reset()
    assert len(info["shipd_vector"]) == 45
    assert info["shipd_labels"] == LABELS
    assert obs.shape == (11,)
    assert info["shipd_feasible"] is True
    assert info["shipd_constraints"]["n"] == 49
    assert info["shipd_constraints"]["feasible"] is True


def test_env45_step_ok_when_feasible():
    env = DesignSearchEnv45(sample_index=3, max_steps=5, seed=2)
    env.reset()
    obs, reward, term, trunc, info = env.step([0.0] * 7)
    assert info.get("shipd_infeasible") is not True
    assert "rejected" in info
