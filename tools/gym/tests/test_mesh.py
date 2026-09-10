from pathlib import Path

from yard_sea_v0.hull import HullState
from yard_sea_v0.mesh import (
    cadquery_available,
    export_hull_stl,
    station_beam,
    taper_fractions,
    try_cadquery_chine,
    write_box_stl,
    write_tapered_prism_stl,
)


def test_box_stl_writes(tmp_path: Path):
    p = write_box_stl(HullState(), tmp_path / "h.stl")
    text = p.read_text()
    assert "solid yard_sea_v0_box" in text
    assert text.count("facet normal") == 12


def test_taper_fractions_cb_and_shipd():
    h = HullState(Cb=0.85, lcb_frac=0.0)
    lb, ls, mid = taper_fractions(h)
    assert mid > 0.4
    assert abs(lb + ls + mid - 1.0) < 1e-9
    lb2, ls2, mid2 = taper_fractions(h, lb_frac=0.25, ls_frac=0.20)
    assert abs(lb2 - 0.25) < 1e-9 and abs(ls2 - 0.20) < 1e-9
    assert mid2 == 0.55


def test_station_beam_mid_full():
    B = 20.0
    lb, ls = 0.25, 0.20
    assert abs(station_beam(0.5, B, lb, ls) - B) < 1e-9
    assert station_beam(0.0, B, lb, ls) < 0.2 * B
    assert station_beam(1.0, B, lb, ls) < B


def test_tapered_prism_richer_than_box(tmp_path: Path):
    h = HullState()
    p = write_tapered_prism_stl(h, tmp_path / "tap.stl", n_stations=11)
    text = p.read_text()
    assert "yard_sea_v0_tapered_prism" in text
    n_facets = text.count("facet normal")
    assert n_facets > 12  # richer than box
    assert n_facets >= 100


def test_export_prefers_non_box(tmp_path: Path):
    h = HullState()
    p, backend = export_hull_stl(h, tmp_path / "exp.stl")
    assert p.exists() and p.stat().st_size > 500
    assert backend in ("cadquery_chine", "tapered_prism")
    assert backend != "box"


def test_cadquery_chine_when_available(tmp_path: Path):
    if not cadquery_available():
        assert try_cadquery_chine(HullState(), tmp_path / "cq.stl") is None
        return
    p = try_cadquery_chine(HullState(), tmp_path / "cq.stl", n_stations=7)
    assert p is not None and p.exists()
    assert p.stat().st_size > 1000
    # binary or ascii STL from CQ exporter
    raw = p.read_bytes()
    assert len(raw) > 1000


def test_shipd_lb_ls_loft_path(tmp_path: Path):
    h = HullState(L=100, B=16, T=6, Cb=0.7)
    p, backend = export_hull_stl(
        h, tmp_path / "shipd_tap.stl", prefer="tapered", lb_frac=0.28, ls_frac=0.22
    )
    assert "Lb=0.280" in p.read_text() or backend == "tapered_prism"
    assert p.stat().st_size > 500
