from yard_sea_v0.gallery import write_gallery
from pathlib import Path


def test_gallery_runs(tmp_path: Path):
    manifest = write_gallery(tmp_path, n_parents=3, steps=15, seed=0)
    assert manifest["n_results"] >= 6
    assert (tmp_path / "summary.md").exists()
    assert (tmp_path / "manifest.json").exists()
    assert manifest["n_results"] > 0
