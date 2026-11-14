"""Integrity of the cited tank reference data (data/reference) and the data catalog."""

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
REF = ROOT / "data" / "reference" / "tank_resistance_reference.json"


def _ref():
    return json.loads(REF.read_text())


def test_reference_hulls_present_with_sources():
    ref = _ref()
    assert set(ref["hulls"]) >= {"KCS", "JBC", "KVLCC2", "DTMB5415"}
    for name, h in ref["hulls"].items():
        assert h["source"] and h["url"].startswith("http"), name
        assert h["points"], name
        for p in h["points"]:
            assert 0.05 < p["Fn"] < 0.5 and 2e-3 < p["CT"] < 8e-3, (name, p)


def test_model_particulars_consistent_with_published_cb_and_scale():
    for name, h in _ref()["hulls"].items():
        m, fs = h["model"], h["full_scale"]
        cb = m["vol"] / (m["Lpp"] * m["B"] * m["T"])
        assert math.isclose(cb, fs["Cb"], rel_tol=3e-3), (name, cb, fs["Cb"])
        assert math.isclose(fs["Lpp"] / m["scale"], m["Lpp"], rel_tol=2e-3), name
        if "S0_over_L2" in m:
            assert math.isclose(m["S0"] / m["Lpp"] ** 2, m["S0_over_L2"], rel_tol=2e-3), name


def test_kcs_matches_tokyo2015_case21_table():
    pts = _ref()["hulls"]["KCS"]["points"]
    assert [p["Fn"] for p in pts] == [0.108, 0.152, 0.195, 0.227, 0.260, 0.282]
    assert [round(p["CT"] * 1e3, 3) for p in pts] == [3.796, 3.641, 3.475, 3.467, 3.711, 4.501]


def test_catalog_lists_every_reference_dataset_with_licence():
    cat = (ROOT / "data" / "catalog.yaml").read_text()
    for h in _ref()["hulls"].values():
        assert f"id: {h['dataset_id']}" in cat
    n_ids = cat.count("\n  - id: ")
    assert n_ids == cat.count("\n    licence: ") and n_ids >= 15


def test_vendored_uci_yacht_shape():
    rows = (ROOT / "data" / "vendored" / "uci_yacht_hydrodynamics.csv").read_text().strip().splitlines()
    assert rows[0].startswith("lcb,cp,") and len(rows) == 309
    assert all(len(r.split(",")) == 7 for r in rows[1:])


def test_raw_cache_is_gitignored():
    gi = (ROOT / "data" / "cache" / ".gitignore").read_text().split()
    assert gi[0] == "*"
