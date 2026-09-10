"""Tests for Ship-D 30k corpus loading and parent sampling."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

from yard_sea_v0.corpus import (
    DEFAULT_VECTORS_PATH,
    corpus_info,
    ensure_input_vectors,
    iter_vectors,
    load_input_vectors,
    sample_parent_indices,
    sample_parents,
)
from yard_sea_v0.hull import evaluate_l0


@pytest.fixture(scope="module")
def vectors_path() -> Path:
    path = ensure_input_vectors()
    assert path.is_file()
    return path


def test_load_input_vectors_shape(vectors_path: Path):
    arr = load_input_vectors(vectors_path)
    assert arr.shape == (30000, 45)
    assert arr.dtype == np.float64
    info = corpus_info(vectors_path)
    assert info.n_vectors == 30000
    assert info.n_dims == 45
    assert info.bytes > 1_000_000


def test_default_path_exists():
    assert DEFAULT_VECTORS_PATH.is_file() or ensure_input_vectors().is_file()


def test_iter_vectors_subset(vectors_path: Path):
    items = list(iter_vectors(vectors_path, indices=[0, 10, 100]))
    assert len(items) == 3
    assert items[0][0] == 0
    assert len(items[0][1].values) == 45


def test_sample_parents_l0_feasible(vectors_path: Path):
    parents = sample_parents(5, seed=42, path=vectors_path, filter_l0=True)
    assert len(parents) == 5
    ok = sum(1 for h in parents if evaluate_l0(h).feasible)
    assert ok >= 3
    for h in parents:
        assert h.L > 0 and h.B > 0 and h.T > 0


def test_sample_parent_indices_deterministic(vectors_path: Path):
    a = sample_parent_indices(4, seed=7, path=vectors_path)
    b = sample_parent_indices(4, seed=7, path=vectors_path)
    assert a == b
    assert len(a) == 4


def test_cli_ingest_and_corpus_search(tmp_path: Path, vectors_path: Path):
    from yard_sea_v0.cli import main

    manifest = tmp_path / "ingest.json"
    rc = main(["ingest-shipd", "--out", str(manifest)])
    assert rc == 0
    assert manifest.is_file()
    import json

    data = json.loads(manifest.read_text())
    assert data["corpus"]["n_vectors"] == 30000

    out = tmp_path / "gal"
    rc = main(
        [
            "run-search",
            "--corpus",
            "2",
            "--steps",
            "3",
            "--seed",
            "1",
            "--out",
            str(out),
        ]
    )
    assert rc == 0
    gal = json.loads((out / "manifest.json").read_text())
    assert gal["use_corpus"] is True
    assert gal["n_parents"] == 2


def test_constraint_filter_with_shipd_surface(vectors_path: Path):
    from yard_sea_v0.corpus import _try_shipd_surface, vector_satisfies_shipd_constraints, load_input_vectors

    ss = _try_shipd_surface()
    if ss is None:
        pytest.skip("shipd_surface unavailable")
    arr = load_input_vectors(vectors_path)
    assert vector_satisfies_shipd_constraints(arr[0]) is True
    idxs = sample_parent_indices(3, seed=3, path=vectors_path, filter_constraints=True)
    assert len(idxs) == 3
