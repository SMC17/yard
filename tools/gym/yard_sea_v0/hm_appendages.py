"""Holtrop & Mennen bulbous-bow and immersed-transom terms (Python mirror of Zig).

Same formulas as ``vendor/yard_zig/resistance/src/holtrop.zig`` (Holtrop &
Mennen 1982, Holtrop 1984), used by the Python ``simplified_py`` fallback so
both L1 paths treat a bulb / transom the same way:

* c_3  = 0.56 A_BT^1.5 / (B T (0.31 sqrt(A_BT) + T_F - h_B))
* c_2  = exp(-1.89 sqrt(c_3))                        (wave-resistance factor)
* c_5  = 1 - 0.8 A_T / (B T C_M)                      (transom factor)
* R_B  = 0.11 exp(-3 P_B^-2) F_ni^3 A_BT^1.5 rho g / (1 + F_ni^2)
  P_B  = 0.56 sqrt(A_BT) / (T_F - 1.5 h_B)
  F_ni = V / sqrt(g (T_F - h_B - 0.25 sqrt(A_BT)) + 0.15 V^2)
* R_TR = 0.5 rho V^2 A_T c_6,  c_6 = 0.2 (1 - 0.2 F_nT) for F_nT < 5 else 0
  F_nT = V / sqrt(2 g A_T / (B + B C_WP))

T_F = T (even keel). Inputs come from ``HullState.abt_m2 / hb_m / at_m2``
(0 = absent), which are read off real hull lines (``hull_lines``) or Ship-D.
"""

from __future__ import annotations

import math


def c3(B: float, T: float, abt: float, hb: float, tf: float | None = None) -> float:
    tf = T if tf is None else tf
    den = B * T * (0.31 * math.sqrt(abt) + tf - hb)
    return 0.56 * abt ** 1.5 / den if abt > 0 and den > 0 else 0.0


def c2(B: float, T: float, abt: float, hb: float, tf: float | None = None) -> float:
    c = c3(B, T, abt, hb, tf)
    return math.exp(-1.89 * math.sqrt(c)) if c > 0 else 1.0


def c5(B: float, T: float, at: float, cm: float) -> float:
    return 1.0 - 0.8 * at / (B * T * cm) if at > 0 else 1.0


def bulb_resistance(V: float, T: float, abt: float, hb: float, rho: float, g: float, tf: float | None = None) -> float:
    tf = T if tf is None else tf
    if abt <= 0:
        return 0.0
    dpb = tf - 1.5 * hb
    if dpb <= 0:
        return 0.0
    pb = 0.56 * math.sqrt(abt) / dpb
    num = tf - hb - 0.25 * math.sqrt(abt)
    if pb <= 0 or num <= 0:
        return 0.0
    fni = V / math.sqrt(g * num + 0.15 * V * V)
    return 0.11 * math.exp(-3.0 / (pb * pb)) * fni ** 3 * abt ** 1.5 * rho * g / (1.0 + fni * fni)


def transom_resistance(V: float, B: float, cwp: float, at: float, rho: float, g: float) -> float:
    if at <= 0:
        return 0.0
    fnt = V / math.sqrt(2.0 * g * at / (B + B * cwp))
    c6 = 0.2 * (1.0 - 0.2 * fnt) if fnt < 5.0 else 0.0
    return 0.5 * rho * V * V * at * c6
