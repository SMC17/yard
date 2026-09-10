"""BoTorch search path smoke tests (skip if botorch/torch absent)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from yard_sea_v0.hull import HullState
from yard_sea_v0.search import _botorch_child, botorch_available, run_search


pytestmark = pytest.mark.skipif(
    not botorch_available(),
    reason="botorch/torch not installed",
)


def test_botorch_child_small_budget_runs():
    row = _botorch_child(HullState(), steps=3, seed=1)
    assert row is not None
    assert row.get("skipped") is not True
    assert row["method"] == "botorch"
    assert "ct" in row
    assert "hull" in row
    assert row["n_bo_steps"] == 3
    assert isinstance(row["ct"], float)


def test_run_search_botorch_opt_in():
    rows = run_search([HullState()], steps=4, seed=2, use_botorch=True)
    methods = {r.get("method") for r in rows}
    assert "random" in methods
    assert "hillclimb" in methods
    assert "botorch" in methods
    bo = next(r for r in rows if r.get("method") == "botorch")
    assert bo.get("skipped") is not True
    assert "ct" in bo
    assert bo.get("parent_index") == 0


def test_run_search_botorch_off_by_default():
    rows = run_search([HullState()], steps=3, seed=3, use_botorch=False)
    assert all(r.get("method") != "botorch" for r in rows)


def test_cli_botorch_flag(tmp_path: Path):
    from yard_sea_v0.cli import main

    rc = main(
        [
            "run-search",
            "--parents",
            "1",
            "--steps",
            "3",
            "--seed",
            "0",
            "--out",
            str(tmp_path / "gal"),
            "--botorch",
        ]
    )
    assert rc == 0
    manifest = json.loads((tmp_path / "gal" / "manifest.json").read_text())
    assert manifest["use_botorch"] is True
    children = list((tmp_path / "gal" / "children").glob("child_*.json"))
    assert children
    methods = {json.loads(p.read_text()).get("method") for p in children}
    assert "botorch" in methods
