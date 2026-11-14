"""Published viscous / transom corrections to Michell on the real lines; envelope only if validated."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

from yard_sea_v0 import hull_lines, michell_corrections as mc, validation as v

REP = Path(__file__).resolve().parents[1] / "reports" / "validation" / "michell_corrections.json"


def test_watanabe_form_factor_formula():
    # k = -0.095 + 25.6 Cb / ((L/B)^2 sqrt(B/T)); KVLCC2 model particulars
    L, B, T, Cb = 320.0, 58.0, 20.8, 0.8098
    assert mc.watanabe_form_factor(L, B, T, Cb) == pytest.approx(1 - 0.095 + 25.6 * Cb / ((L / B) ** 2 * np.sqrt(B / T)))
    assert 1.25 < mc.watanabe_form_factor(L, B, T, Cb) < 1.35  # full form
    assert mc.watanabe_form_factor(142.0, 19.06, 6.15, 0.507) < 1.1  # slender combatant


def test_hm_transom_c6():
    assert mc.hm1984_transom_c6(0.0) == pytest.approx(0.2)
    assert mc.hm1984_transom_c6(2.5) == pytest.approx(0.1)
    assert mc.hm1984_transom_c6(5.0) == 0.0 and mc.hm1984_transom_c6(9.0) == 0.0


def test_virtual_appendage_geometry():
    Z = np.linspace(0, -1.0, 11)
    X = np.linspace(0, 10.0, 21)
    Y = np.ones((21, 11))
    Y[0, 5:] = 0.0  # transom wet to |z| = 0.4
    Y2, X2, Z2 = mc.add_virtual_appendage(Y, X, Z, length=6.68 * 0.4, t_t=0.4)
    n = Y2.shape[0] - Y.shape[0]
    assert n % 2 == 0 and n > 0 and Y2.shape[0] % 2 == 1  # nx stays odd for Filon
    assert np.allclose(np.diff(X2), X[1] - X[0]) and X2[0] == pytest.approx(0.0)
    depth = [(-Z2[row > 0]).max() if (row > 0).any() else 0.0 for row in Y2[:n]]
    assert np.all(np.diff(depth) >= -1e-12)  # appendage deepens toward the transom
    assert depth[-1] <= 0.4 + 1e-12
    assert np.array_equal(Y2[n:], Y)


def test_no_transom_flag_means_no_appendage():
    if not hull_lines.available("KVLCC2"):
        pytest.skip("KVLCC2 lines not fetched")
    c = next(x for x in v.tank_cases() if x.hull == "KVLCC2")
    p = mc.michell_lines_corrected(c, form_factor="hm1984_gym", transom=False)
    assert p["transom"]["applied"] is False
    base = v.michell_lines(c)
    assert p["CT"] == pytest.approx(base["CT"], rel=1e-9)  # reproduces the existing oracle


def test_committed_report_not_validated_no_envelope():
    r = json.loads(REP.read_text())
    s = r["stats"]
    base, prim = s["baseline (HM 1+k, open stern)"], s[r["primary"]]
    assert prim["mean_abs_E_pct"] < base["mean_abs_E_pct"]  # error drops ...
    assert prim["mean_abs_E_pct"] > r["tol_pct"]  # ... but not to the tolerance
    assert r["validated"] is False and r["envelope"] is None
    assert "michell_lines_corrected" not in v.ORACLES
