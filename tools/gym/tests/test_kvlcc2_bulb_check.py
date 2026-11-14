"""KVLCC2 bulb inputs vs an independent published set; the bulb worsening is documented, not tuned."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from yard_sea_v0 import hull_lines, kvlcc2_bulb_check as kb, validation as v

REP = Path(__file__).resolve().parents[1] / "reports" / "validation" / "kvlcc2_bulb_check.json"


@pytest.mark.skipif(not hull_lines.available("KVLCC2"), reason="KVLCC2 lines not fetched")
def test_lines_bulb_inputs_match_published_within_1pct():
    c = next(x for x in v.tank_cases() if x.hull == "KVLCC2")
    p = c.lines()
    lam = kb.LPP_FULL / c.L
    assert p.A_BT * lam**2 == pytest.approx(kb.PUBLISHED["A_BT_m2"], rel=0.01)
    assert p.h_B * lam == pytest.approx(kb.PUBLISHED["h_B_m"], rel=0.01)


def test_committed_report_finding():
    r = json.loads(REP.read_text())
    runs = r["runs"]
    lines, bare = runs["lines-derived bulb (current)"], runs["bare (no bulb, no transom)"]
    assert lines["E_pct"] < bare["E_pct"] < 0  # bulb makes the over-prediction worse
    assert bare["Cf_1k"] > r["CT_measured"]  # viscous term alone over-predicts
    assert r["implied_one_plus_k_max"] < bare["one_plus_k"]
    assert abs(r["lines_vs_published"]["A_BT_pct"]) < 1.0
