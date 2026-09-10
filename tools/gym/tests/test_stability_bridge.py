"""Stability bridge soft floors."""

from yard_sea_v0.hull import HullState
from yard_sea_v0.stability_bridge import gz_at_30_proxy, stability_bonus


def test_default_hull_has_positive_bonus():
    h = HullState()
    assert h.gm0() > 0.15
    assert gz_at_30_proxy(h) > 0.0
    assert 0.0 < stability_bonus(h) <= 1.0


def test_tender_hull_low_bonus():
    # Extremely narrow / high KG exploratory — may fail GM floor
    h = HullState(L=80, B=8, T=6, Cb=0.7, kg_frac=0.95)
    b = stability_bonus(h)
    assert 0.0 <= b <= 1.0
