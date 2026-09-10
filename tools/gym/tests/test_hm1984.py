"""HM1984 Zig L1 teacher tests — finite Ct; no parity vs simplified."""

from __future__ import annotations

import math
import subprocess
from pathlib import Path

import pytest

from yard_sea_v0.hull import HullState
from yard_sea_v0.zig_bridge import (
    estimate_resistance_zig,
    resolve_zig_binary,
    zig_available,
)

_ZIG_GYM = Path(__file__).resolve().parents[1] / "zig_gym"
_BUILD_FAIL_MSG = (
    "yard_sea_zig HM1984 build unavailable; run `cd zig_gym && zig build` "
    "(Zig 0.15.2 + vendor/yard_zig/resistance)."
)


def _ensure_built() -> bool:
    if zig_available():
        return True
    zig = Path("/usr/local/bin/zig")
    if not zig.is_file() or not _ZIG_GYM.is_dir():
        return False
    try:
        proc = subprocess.run(
            [str(zig), "build"],
            cwd=_ZIG_GYM,
            capture_output=True,
            text=True,
            timeout=120,
        )
        return proc.returncode == 0 and zig_available()
    except Exception:
        return False


@pytest.fixture(scope="module")
def hm1984_ready():
    if not _ensure_built():
        pytest.xfail(_BUILD_FAIL_MSG)
    try:
        resolve_zig_binary()
    except FileNotFoundError:
        pytest.xfail(_BUILD_FAIL_MSG)


def test_hm1984_finite_ct(hm1984_ready):
    h = HullState()
    r = estimate_resistance_zig(h, fidelity="hm1984")
    assert math.isfinite(r.Ct)
    assert r.Ct > 0
    assert math.isfinite(r.Rt_N) and r.Rt_N > 0
    assert math.isfinite(r.Rn) and r.Rn > 0
    assert math.isfinite(r.Cf) and r.Cf > 0
    assert "hm1984" in r.fidelity.lower() or "1984" in r.fidelity


def test_hm1984_not_required_to_match_simplified(hm1984_ready):
    h = HullState()
    simp = estimate_resistance_zig(h, fidelity="simplified")
    hm = estimate_resistance_zig(h, fidelity="hm1984")
    # Document intentional divergence — both finite, not parity-locked.
    assert math.isfinite(simp.Ct) and math.isfinite(hm.Ct)
    assert simp.fidelity != hm.fidelity or "simplified" in simp.fidelity.lower()


def test_teacher_zig_l1_prefers_hm1984(hm1984_ready):
    from yard_sea_v0.teachers.zig_l1 import estimate_l1, teacher_meta

    r = estimate_l1(HullState(), fidelity="hm1984")
    assert math.isfinite(r.Ct) and r.Ct > 0
    meta = teacher_meta()
    assert meta["zig_available"] is True


def test_resistance_l1_prefer_flag(hm1984_ready):
    from yard_sea_v0.resistance_l1 import estimate_resistance

    r = estimate_resistance(HullState(), prefer_zig_hm1984=True)
    assert math.isfinite(r.Ct)
    assert "1984" in r.fidelity or r.fidelity.endswith("hm1984") or "hm1984" in r.fidelity.lower()
