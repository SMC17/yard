"""Holtrop bulb / transom terms: Python mirror == Zig HM1984; plumbing through HullState."""
from __future__ import annotations

import json
import math
import subprocess

import pytest

from yard_sea_v0 import hm_appendages as hma
from yard_sea_v0.hull import G, RHO_SW, HullState
from yard_sea_v0.monitors import apply_action
from yard_sea_v0.resistance_l1 import estimate_resistance


def _zig():
    try:
        from yard_sea_v0.zig_bridge import resolve_zig_binary

        return resolve_zig_binary()
    except FileNotFoundError:
        return None


def test_python_terms_match_zig_full_path():
    b = _zig()
    if b is None:
        pytest.skip("zig_gym binary not built")
    L, B, T, Cb, Cm, Cwp, Fn = 230.0, 32.2, 10.8, 0.65, 0.985, 0.83, 0.26
    abt, hb, at = 29.3, 5.23, 40.0  # A_T large enough that F_nT < 5
    vol, S = L * B * T * Cb, 9424.0
    args = [L, B, T, vol, S, Cb, Cm, Cb / Cm, Cwp, -1.48, 0.0, Fn, 1.19e-6, RHO_SW, abt, T, hb, at]
    out = subprocess.run([str(b), "hm1984_full", *map(repr, args)], capture_output=True, text=True, check=True)
    z = json.loads(out.stdout.strip().splitlines()[-1])["l1"]
    V = Fn * math.sqrt(G * L)
    q = 0.5 * RHO_SW * V * V * S
    assert z["c_2"] == pytest.approx(hma.c2(B, T, abt, hb), rel=1e-12)
    assert z["c_5"] == pytest.approx(hma.c5(B, T, at, Cm), rel=1e-12)
    assert z["C_bulb"] == pytest.approx(hma.bulb_resistance(V, T, abt, hb, RHO_SW, G) / q, rel=1e-9)
    assert z["C_tr"] == pytest.approx(hma.transom_resistance(V, B, Cwp, at, RHO_SW, G) / q, rel=1e-9)
    assert z["C_tr"] > 0 and z["c_2"] < 1 and z["c_5"] < 1


def test_no_appendages_is_unchanged():
    h = HullState()
    assert h.appendages() == {"abt_m2": 0.0, "hb_m": 0.0, "at_m2": 0.0}
    assert hma.c2(20, 8, 0, 0) == 1.0 and hma.c5(20, 8, 0, 0.98) == 1.0
    assert hma.bulb_resistance(5.0, 8.0, 0, 0, RHO_SW, G) == 0.0


@pytest.mark.parametrize("prefer_zig", [True, False])
def test_bulb_lowers_wave_term_at_design_speed(prefer_zig):
    if prefer_zig and _zig() is None:
        pytest.skip("zig_gym binary not built")
    base = HullState(L=230, B=32.2, T=10.8, Cb=0.65, lcb_frac=-0.0148, Fn=0.26)
    bulb = HullState(**{**base.__dict__, "abt_m2": 29.3, "hb_m": 5.23})
    a, b = estimate_resistance(base, prefer_zig_hm1984=prefer_zig), estimate_resistance(bulb, prefer_zig_hm1984=prefer_zig)
    assert b.Cw < a.Cw and b.Ct < a.Ct


def test_appendages_survive_actions():
    h = HullState(abt_m2=10.0, hb_m=3.0, at_m2=2.0)
    h2 = apply_action(h, [0.5, -0.5, 0.2, 0.1, 0.0, 0.0, 0.1])
    assert h2.appendages() == h.appendages() and h2.L != h.L


def test_shipd_appendages_opt_in():
    from yard_sea_v0.shipd import load_sample_vectors, project_to_hull

    vs = load_sample_vectors()
    assert project_to_hull(vs[0]).appendages() == {"abt_m2": 0.0, "hb_m": 0.0, "at_m2": 0.0}
    hs = [project_to_hull(v, appendages=True) for v in vs]
    bulbs = [h for h, v in zip(hs, vs) if v.as_dict().get("bit_BB", 0) >= 0.5]
    assert any(h.abt_m2 > 0 for h in bulbs)
    for h in hs:
        assert h.abt_m2 >= 0 and h.at_m2 >= 0
        if h.abt_m2 > 0:
            assert 0 < h.hb_m < h.T
            assert h.abt_m2 < h.B * h.T
