"""Default L1 path prefers Zig HM1984; Python simplified_py is fallback."""

from __future__ import annotations

import math
from unittest import mock

import pytest

from yard_sea_v0.hull import HullState
from yard_sea_v0.resistance_l1 import estimate_resistance
from yard_sea_v0.zig_bridge import zig_available


def test_default_estimate_prefers_hm1984_zig_when_binary_present():
    if not zig_available():
        pytest.skip("yard_sea_zig not built")
    r = estimate_resistance(HullState())  # prefer_zig_hm1984 defaults True
    assert math.isfinite(r.Ct) and r.Ct > 0
    assert r.fidelity == "hm1984_zig"


def test_explicit_false_forces_simplified_py():
    r = estimate_resistance(HullState(), prefer_zig_hm1984=False)
    assert math.isfinite(r.Ct) and r.Ct > 0
    assert r.fidelity == "simplified_py"


def test_fallback_when_zig_unavailable():
    with mock.patch("yard_sea_v0.zig_bridge.zig_available", return_value=False):
        r = estimate_resistance(HullState(), prefer_zig_hm1984=True)
    assert r.fidelity == "simplified_py"
    assert math.isfinite(r.Ct) and r.Ct > 0


def test_fallback_when_zig_raises():
    with mock.patch("yard_sea_v0.zig_bridge.zig_available", return_value=True):
        with mock.patch(
            "yard_sea_v0.zig_bridge.estimate_resistance_zig",
            side_effect=RuntimeError("boom"),
        ):
            r = estimate_resistance(HullState(), prefer_zig_hm1984=True)
    assert r.fidelity == "simplified_py"
    assert math.isfinite(r.Ct) and r.Ct > 0


def test_env_evidence_notes_fidelity():
    from yard_sea_v0.env import DesignSearchEnv

    env = DesignSearchEnv(parent=HullState(), max_steps=2, seed=0)
    env.reset()
    _, _, _, _, info = env.step([0.05, 0, 0, 0, 0, 0, 0])
    if info.get("rejected"):
        pytest.skip("monitor rejected step")
    assert "l1_fidelity" in info
    pack = env.evidence_packs[-1]
    assert pack["resistance"]["fidelity"] in ("hm1984_zig", "simplified_py")
    claim = next(c for c in pack["claims"] if c["id"] == "drag_rank_l1")
    assert claim.get("fidelity") in ("hm1984_zig", "simplified_py")
    assert "hm1984_zig" in claim["statement"] or "simplified_py" in claim["statement"]
