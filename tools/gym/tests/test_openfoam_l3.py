"""Tests for OpenFOAM L3 teacher scaffold (mocked; no FOAM required)."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest

from yard_sea_v0.hull import HullState
from yard_sea_v0.mesh import write_box_stl
from yard_sea_v0.teachers.openfoam_l3 import (
    FIDELITY_OPENFOAM,
    FIDELITY_PENDING,
    OpenFOAMAvailability,
    detect_openfoam,
    parse_force_coeffs,
    prepare_case,
    run_teacher,
)


def test_detect_openfoam_returns_dataclass():
    avail = detect_openfoam()
    assert isinstance(avail, OpenFOAMAvailability)
    d = avail.to_dict()
    assert "available" in d
    assert "docker" in d


def test_prepare_case_copies_stl_and_fills_placeholders(tmp_path: Path):
    stl = write_box_stl(HullState(L=100.0, B=16.0, T=7.0, Fn=0.18), tmp_path / "h.stl")
    case = prepare_case(stl, Fn=0.18, out_dir=tmp_path / "case", L=100.0, B=16.0, T=7.0)
    assert (case / "constant" / "triSurface" / "hull.stl").is_file()
    assert (case / "system" / "controlDict").is_file()
    assert (case / "Allrun").is_file()
    u_text = (case / "0" / "U").read_text()
    assert "__UX__" not in u_text
    assert "uniform (" in u_text
    ctrl = (case / "system" / "controlDict").read_text()
    assert "__MAG_U_INF__" not in ctrl
    assert "__L_REF__" not in ctrl
    meta = (case / "yard_sea_prepare.json").read_text()
    assert "L3_pending" in meta


def test_parse_force_coeffs_last_row(tmp_path: Path):
    p = tmp_path / "forceCoeffs.dat"
    p.write_text(
        "# Time Cd Cl CmRoll CmPitch CmYaw\n"
        "1 0.11 0.01 0 0.02 0\n"
        "2 0.105 0.012 0 0.019 0\n"
    )
    c = parse_force_coeffs(p)
    assert c is not None
    assert c["Cd"] == pytest.approx(0.105)
    assert c["Cl"] == pytest.approx(0.012)


def test_parse_force_coeffs_missing(tmp_path: Path):
    assert parse_force_coeffs(tmp_path / "nope.dat") is None


def test_run_teacher_skips_without_foam(tmp_path: Path):
    stl = write_box_stl(HullState(), tmp_path / "h.stl")
    fake = OpenFOAMAvailability()
    result = run_teacher(
        stl, 0.2, tmp_path / "case", availability=fake, L=120.0
    )
    assert result["skipped"] is True
    assert result["fidelity"] == FIDELITY_PENDING
    assert result["skip_reason"] == "openfoam_unavailable"
    assert (tmp_path / "case" / "constant" / "triSurface" / "hull.stl").is_file()


def test_run_teacher_parses_mocked_coeffs(tmp_path: Path):
    stl = write_box_stl(HullState(L=120.0), tmp_path / "h.stl")
    case = prepare_case(stl, 0.2, tmp_path / "case", L=120.0)
    post = case / "postProcessing" / "forceCoeffs1" / "0"
    post.mkdir(parents=True)
    (post / "forceCoeffs.dat").write_text(
        "# Time Cd Cl Cm\n"
        "10 0.0045 0.0 0.0\n"
    )
    avail = OpenFOAMAvailability(foam_bin="/usr/bin/potentialFoam")

    def fake_run(*args, **kwargs):
        class R:
            returncode = 0
            stdout = ""
            stderr = ""

        return R()

    with patch("yard_sea_v0.teachers.openfoam_l3.subprocess.run", side_effect=fake_run):
        result = run_teacher(
            case_dir=case, Fn=0.2, L=120.0, availability=avail, run=True
        )
    assert result["skipped"] is False
    assert result["fidelity"] == FIDELITY_OPENFOAM
    assert result["Cd"] == pytest.approx(0.0045)
    assert result["Ct"] == pytest.approx(0.0045)


def test_cli_l3_flag_noops(tmp_path: Path):
    from yard_sea_v0.cli import main

    rc = main(
        [
            "run-search",
            "--parents",
            "1",
            "--steps",
            "2",
            "--seed",
            "0",
            "--out",
            str(tmp_path / "gal"),
            "--l3-openfoam",
        ]
    )
    assert rc == 0
    import json

    manifest = json.loads((tmp_path / "gal" / "manifest.json").read_text())
    assert manifest["l3_openfoam"] is True
    assert "available" in manifest["l3_availability"]
    assert len(manifest["l3_summaries"]) >= 1
    # FOAM may or may not be on the shared box; pending OR openfoam are both OK
    assert all(
        s["fidelity"] in (FIDELITY_PENDING, FIDELITY_OPENFOAM) for s in manifest["l3_summaries"]
    )
