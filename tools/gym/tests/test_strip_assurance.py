from yard_sea_v0.env import DesignSearchEnv
from yard_sea_v0.strip_assurance import strip_overlay


def test_strip_overlay_on_env_step():
    env = DesignSearchEnv(max_steps=3, seed=0, evidence_dir=None)
    env.reset()
    obs, reward, term, trunc, info = env.step([0.0] * 7)
    packs = info.get("evidence") or env.evidence_packs
    assert packs
    sa = packs[-1]["strip_assurance"]
    assert sa["not_certification"] is True
    assert sa["assurance_level"] in ("L0_reject", "L1_rank")
    assert "validation_gates" in sa


def test_overlay_reject():
    sa = strip_overlay({"monitor": {"allow": False}, "l0": {"feasible": False}, "claims": []})
    assert sa["assurance_level"] == "L0_reject"
