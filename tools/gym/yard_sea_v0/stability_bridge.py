"""Soft stability signal for gym reward using box-barge GM / IS-code floors.

Replicates the exploratory GM0 floor already in L0; adds a cheap GZ@30 proxy
without importing the full oracle (keeps tools/gym self-contained).
"""

from __future__ import annotations

import math

from .hull import HullState


def gz_at_30_proxy(h: HullState) -> float:
    """Wall-sided GZ at 30 deg using GM0 and BM_T (exploratory)."""
    gm = h.gm0()
    bm = h.bm_t()
    phi = math.radians(30.0)
    tan_phi = math.tan(phi)
    return (gm + 0.5 * bm * tan_phi * tan_phi) * math.sin(phi)


def stability_bonus(h: HullState) -> float:
    """Return [0, 1] bonus for meeting exploratory IS-like floors."""
    score = 0.0
    if h.gm0() >= 0.15:
        score += 0.4
    if gz_at_30_proxy(h) >= 0.20:
        score += 0.6
    return score
