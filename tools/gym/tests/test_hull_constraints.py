from yard_sea_v0.hull import HullState, evaluate_l0


def test_default_feasible():
    r = evaluate_l0(HullState())
    assert r.feasible, r.violations


def test_bad_cb_rejected():
    h = HullState(Cb=0.2)
    r = evaluate_l0(h)
    assert not r.feasible
    assert any("Cb" in v for v in r.violations)


def test_low_gm_rejected():
    h = HullState(L=100, B=10, T=8, Cb=0.8, kg_frac=0.95)
    r = evaluate_l0(h)
    assert not r.feasible
