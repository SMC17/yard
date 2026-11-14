"""Tests for Capytaine L2 panel/BEM teacher."""

from __future__ import annotations

import json
import os
from pathlib import Path
from unittest.mock import patch

import numpy as np
import pytest

from yard_sea_v0.hull import HullState
from yard_sea_v0.teachers.panel_l2 import (
    FIDELITY,
    FIDELITY_PENDING,
    PanelAvailability,
    detect,
    encounter_omega,
    run,
)

# Capytaine is optional (requirements.txt lists it commented out). Tests that need a
# real BEM solve skip when it is absent, unless YARD_REQUIRE_CAPYTAINE=1 (set by the
# dedicated CI job that installs it), in which case absence is a hard failure.
_HAVE_CAPYTAINE = detect().available
needs_capytaine = pytest.mark.skipif(
    not _HAVE_CAPYTAINE and os.environ.get("YARD_REQUIRE_CAPYTAINE") != "1",
    reason="capytaine not installed (optional L2 dependency)",
)


@needs_capytaine
def test_detect_capytaine():
    avail = detect()
    assert isinstance(avail, PanelAvailability)
    assert avail.available is True
    assert avail.version is not None


def test_encounter_omega_positive():
    om = encounter_omega(120.0)
    assert om > 0
    assert np.isfinite(om)


def test_run_skips_when_missing():
    fake = PanelAvailability(capytaine=False, error="not installed")
    r = run(HullState(), availability=fake)
    assert r["skipped"] is True
    assert r["skip_reason"] == "capytaine_missing"
    assert r["fidelity"] == FIDELITY_PENDING
    assert r["Cd"] is None
    assert "not ittc" in r["notes"].lower()


@needs_capytaine
def test_run_parallelepiped_finite_cw_cd():
    h = HullState(L=20.0, B=4.0, T=2.0, Cb=0.7, Fn=0.20)
    r = run(h, resolution=(8, 3, 3))
    assert r["skipped"] is False, r.get("skip_reason")
    assert r["fidelity"] == FIDELITY
    assert r["teacher"] == "panel_l2"
    assert r["backend"] == "capytaine"
    assert r["geom_source"] == "parallelepiped"
    assert np.isfinite(r["Cw"])
    assert np.isfinite(r["Cd"])
    assert r["Cd"] == r["Cd_like"]
    assert np.isfinite(r["Cw_like"])
    assert r["nb_faces"] >= 4
    assert "not ittc" in r["notes"].lower()
    assert "not class" in r["notes"].lower()


@needs_capytaine
def test_run_stl_path(tmp_path: Path):
    from yard_sea_v0.mesh import export_hull_stl

    h = HullState(L=10.0, B=2.0, T=1.0, Cb=0.7, Fn=0.18)
    stl = tmp_path / "hull.stl"
    export_hull_stl(h, stl)
    r = run(h, stl_path=stl, resolution=(6, 3, 3))
    # STL path may succeed or fail cleanly depending on mesh orientation/quality
    assert r["teacher"] == "panel_l2"
    if r["skipped"]:
        assert r["fidelity"] == FIDELITY_PENDING
        assert r["skip_reason"] in {"stl_mesh_empty", "capytaine_failed"}
    else:
        assert r["fidelity"] == FIDELITY
        assert r["geom_source"].startswith("stl:")
        assert np.isfinite(r["Cd"])


@needs_capytaine
def test_cli_l2_flag(tmp_path: Path):
    from yard_sea_v0.cli import main

    # Capytaine BEM is slower — keep parents/steps tiny; still exercises wiring.
    rc = main(
        [
            "run-search",
            "--parents",
            "1",
            "--steps",
            "1",
            "--seed",
            "0",
            "--out",
            str(tmp_path / "gal"),
            "--l2-panel",
        ]
    )
    assert rc == 0
    manifest = json.loads((tmp_path / "gal" / "manifest.json").read_text())
    assert manifest["l2_panel"] is True
    assert manifest["l2_availability"]["available"] is True
    assert len(manifest["l2_summaries"]) >= 1
    assert all(s["fidelity"] in (FIDELITY, FIDELITY_PENDING) for s in manifest["l2_summaries"])


def test_gallery_l2_skip_records_pending(tmp_path: Path):
    from yard_sea_v0.gallery import write_gallery

    fake = PanelAvailability(capytaine=False, error="forced")
    with (
        patch("yard_sea_v0.gallery.detect_panel", return_value=fake),
        patch("yard_sea_v0.gallery.run_panel") as rp,
    ):
        rp.return_value = {
            "fidelity": FIDELITY_PENDING,
            "skipped": True,
            "skip_reason": "capytaine_missing",
            "Cw": None,
            "Cd": None,
            "Ct": None,
            "backend": None,
            "teacher": "panel_l2",
        }
        manifest = write_gallery(
            tmp_path,
            n_parents=1,
            steps=1,
            seed=0,
            l2_panel=True,
        )
    assert manifest["l2_panel"] is True
    assert manifest["l2_availability"]["available"] is False
    assert len(manifest["l2_summaries"]) >= 1
    assert manifest["l2_summaries"][0]["skipped"] is True
