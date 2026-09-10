from pathlib import Path

from yard_sea_v0.hull import HullState
from yard_sea_v0.mesh import write_box_stl


def test_box_stl_writes(tmp_path: Path):
    p = write_box_stl(HullState(), tmp_path / "h.stl")
    text = p.read_text()
    assert "solid yard_sea_v0_box" in text
    assert text.count("facet normal") == 12
