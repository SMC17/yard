"""Real hull lines (fetched, not committed): derived hydrostatics vs published particulars."""
from __future__ import annotations

import numpy as np
import pytest

from yard_sea_v0 import hull_lines as hl
from yard_sea_v0.validation import load_reference

pytest.importorskip("scipy")

# Published particulars at the scale of each geometry file (data/reference + workshop pages).
PUB = {
    "KCS": {"vol": 52030.0, "Cb": 0.6505, "lcb_pct": -1.48, "S": 9424.0, "B": 32.2},
    "KVLCC2": {"vol": 312622.0, "Cb": 0.8098, "lcb_pct": 3.48, "S": 8.1638 * 58.0 ** 2, "B": 58.0},
    "DTMB5415": {"vol": 0.554, "Cb": 0.506, "lcb_pct": -0.683, "S": 4.861, "B": 0.768},
}


@pytest.mark.parametrize("hull", hl.HULLS)
def test_lines_hydrostatics_match_published(hull):
    if not hl.available(hull):
        pytest.skip("hull lines not fetched (python data/fetch/fetch_yard_data.py)")
    p = hl.particulars(hull)
    pub = PUB[hull]
    assert p.vol == pytest.approx(pub["vol"], rel=0.01)
    assert p.Cb == pytest.approx(pub["Cb"], abs=0.006)
    assert p.B == pytest.approx(pub["B"], rel=0.005)
    assert p.lcb_pct == pytest.approx(pub["lcb_pct"], abs=0.15)
    assert p.S == pytest.approx(pub["S"], rel=0.04)
    assert 0.5 < p.Cwp < 0.95 and 0.8 < p.Cm <= 1.0


def test_bulb_and_transom_read_off_lines():
    if not all(hl.available(h) for h in hl.HULLS):
        pytest.skip("hull lines not fetched")
    kcs, kv, d5 = (hl.particulars(h) for h in hl.HULLS)
    # Bulbous bows: A_BT a few % of the midship area, centroid below half draft.
    for p in (kcs, kv):
        assert 0.03 < p.A_BT / (p.B * p.T * p.Cm) < 0.2
        assert 0.3 * p.T < p.h_B < 0.6 * p.T
    # 5415 has a sonar dome aft of the FP, so no bulb area at the FP.
    assert d5.A_BT == pytest.approx(0.0, abs=1e-6)
    # Transoms: KCS dry at rest (tiny), 5415 slightly immersed, KVLCC2 none.
    assert kcs.A_T / (kcs.B * kcs.T) < 0.002
    assert 0.005 < d5.A_T / (d5.B * d5.T) < 0.05
    assert kv.A_T == 0.0


def test_scaling_to_model():
    if not hl.available("KCS"):
        pytest.skip("KCS lines not fetched")
    ref = load_reference()["hulls"]["KCS"]["model"]
    p = hl.particulars("KCS").scaled(230.0 / ref["Lpp"])
    assert p.vol == pytest.approx(ref["vol"], rel=0.01)
    assert p.Lpp == pytest.approx(ref["Lpp"], rel=1e-9)


def test_michell_offsets_shape():
    if not hl.available("KCS"):
        pytest.skip("KCS lines not fetched")
    Y, X, Z = hl.michell_offsets("KCS", scale_to_L=7.2786, nx=41, nz=11)
    assert Y.shape == (41, 11) and X[0] == 0.0 and Z[0] == 0.0 and Z[-1] < 0
    assert np.nanmax(Y) == pytest.approx(1.019 / 2, rel=0.02)
