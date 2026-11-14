from yard_sea_v0.env import DesignSearchEnv
from yard_sea_v0.hull import HullState


def test_evidence_emitted():
    env = DesignSearchEnv(parent=HullState(), max_steps=3, seed=0)
    env.reset()
    env.step([0.1, 0, 0, 0, 0, 0, 0])
    assert len(env.evidence_packs) >= 1
    pack = env.evidence_packs[0]
    assert pack["schema"] == "yard_sea_v0.evidence.v2"
    assert "yard_sea_v0.evidence.v1" in pack["schema_compat"]
    assert "odd" in pack and "claims" in pack and "gsn_stub" in pack
    assert pack["agent_class"] == "learned_offline"
    assert pack["odd"]["limits"]["not_ittc_powering"] is True
