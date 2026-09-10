"""Tests for OpenFOAM L3 teacher (mocked FOAM + fixture forceCoeffs)."""

from __future__ import annotations

import os
from pathlib import Path
from unittest.mock import patch

import pytest

from yard_sea_v0.hull import HullState
from yard_sea_v0.mesh import write_box_stl
from yard_sea_v0.teachers.openfoam_l3 import (
    FIDELITY_OPENFOAM,
    FIDELITY_PENDING,
    FIDELITY_POTENTIAL,
    FIDELITY_RANS,
    OpenFOAMAvailability,
    detect_openfoam,
    native_forces_health,
    parse_force_coeffs,
    prepare_case,
    run_teacher,
    stl_bbox,
    _sha1_preload_so,
    _skip_reason_hint,
)

FIXTURES = Path(__file__).resolve().parent / "fixtures"
REPO = Path(__file__).resolve().parents[1]


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
    assert (case / "system" / "snappyHexMeshDict").is_file()
    assert (case / "system" / "meshQualityDict").is_file()
    assert (case / "system" / "forceCoeffs1").is_file()
    assert (case / "Allrun").is_file()
    u_text = (case / "0" / "U").read_text()
    assert "__UX__" not in u_text
    assert "uniform (" in u_text
    ctrl = (case / "system" / "controlDict").read_text()
    assert "__MAG_U_INF__" not in ctrl
    assert "__L_REF__" not in ctrl
    assert "forceCoeffs" in ctrl
    bm = (case / "system" / "blockMeshDict").read_text()
    assert "__XMIN__" not in bm
    assert "__NX__" not in bm
    snap = (case / "system" / "snappyHexMeshDict").read_text()
    assert "__LOCATION_IN_MESH__" not in snap
    assert "locationInMesh" in snap
    meta = (case / "yard_sea_prepare.json").read_text()
    assert "L3_pending" in meta


def test_stl_bbox_ascii_box(tmp_path: Path):
    stl = write_box_stl(HullState(L=120.0, B=20.0, T=8.0), tmp_path / "box.stl")
    bb = stl_bbox(stl)
    assert bb is not None
    xmin, xmax, ymin, ymax, zmin, zmax = bb
    assert xmax - xmin == pytest.approx(120.0)
    assert ymax - ymin == pytest.approx(20.0)
    assert zmax - zmin == pytest.approx(8.0)


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


def test_parse_force_coeffs_v1912_fixture():
    p = FIXTURES / "forceCoeffs.dat"
    c = parse_force_coeffs(p)
    assert c is not None
    assert c["Cd"] == pytest.approx(0.1912)
    assert c["Cl"] == pytest.approx(0.010)
    assert c["Cm"] == pytest.approx(0.017)


def test_parse_force_coeffs_short_fixture():
    c = parse_force_coeffs(FIXTURES / "forceCoeffs_short.dat")
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
        (FIXTURES / "forceCoeffs.dat").read_text()
    )
    mesh = case / "constant" / "polyMesh"
    mesh.mkdir(parents=True, exist_ok=True)
    (mesh / "boundary").write_text(
        "6\n(\nhull\n{\n    type wall;\n    nFaces 10;\n    startFace 0;\n}\n)\n"
    )
    avail = OpenFOAMAvailability(foam_bin="/usr/bin/potentialFoam")

    def fake_run(*args, **kwargs):
        class R:
            returncode = 0
            stdout = "End\n"
            stderr = ""

        return R()

    with patch("yard_sea_v0.teachers.openfoam_l3.subprocess.run", side_effect=fake_run):
        result = run_teacher(
            case_dir=case, Fn=0.2, L=120.0, availability=avail, run=True
        )
    assert result["skipped"] is False
    assert result["fidelity"] in (FIDELITY_POTENTIAL, FIDELITY_RANS)
    assert result["Cd"] == pytest.approx(0.1912)
    assert result["Ct"] == pytest.approx(0.1912)
    assert result["solver"] in ("potentialFoam", "simpleFoam")


def test_cli_l3_flag_noops(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    from yard_sea_v0.cli import main

    monkeypatch.setenv("YARD_SEA_L3_SKIP_SOLVE", "1")
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
    ok = (FIDELITY_PENDING, FIDELITY_OPENFOAM, FIDELITY_POTENTIAL, FIDELITY_RANS)
    assert all(s["fidelity"] in ok for s in manifest["l3_summaries"])


@pytest.mark.integration
def test_forcecoeffs_integration_smoke(tmp_path: Path):
    """Real snappyHexMesh + solver if native FOAM is present; skip on timeout/disk."""
    avail = detect_openfoam()
    if not avail.foam_bin:
        pytest.skip("native OpenFOAM not on PATH")
    stl = REPO / "out" / "sample_tapered_prism.stl"
    if not stl.is_file():
        stl = write_box_stl(HullState(L=120.0, B=20.0, T=8.0), tmp_path / "hull.stl")
    out = tmp_path / "foam_case"
    result = run_teacher(
        stl,
        0.2,
        out,
        L=120.0,
        B=20.0,
        T=8.0,
        availability=avail,
        timeout_s=float(os.environ.get("YARD_SEA_L3_TIMEOUT", "180")),
        solver="auto",
    )
    if result["skipped"]:
        pytest.skip(f"L3 smoke skipped: {result.get('skip_reason')}")
    assert result["fidelity"] in (FIDELITY_POTENTIAL, FIDELITY_RANS)
    assert result["Cd"] is not None
    assert result["skipped"] is False


def test_native_forces_health_shape():
    h = native_forces_health(ensure_preload=True)
    assert "ok" in h and "method" in h and "detail" in h
    assert "sha1_bug" in h
    # On this Debian box we expect sha1 bug + preload, but keep soft if layout differs.
    if h.get("sha1_bug") and _sha1_preload_so() is not None:
        assert h["ok"] is True
        assert h["method"] == "sha1_preload"


def test_detect_includes_native_forces_fields():
    d = detect_openfoam().to_dict()
    assert "native_forces_ok" in d
    assert "native_forces_method" in d
    assert "native_forces_detail" in d


def test_skip_reason_hint_sha1():
    hint = _skip_reason_hint("forceCoeffs_sha1_bug")
    assert "OSHA1stream" in hint or "sha1buf" in hint
    assert "OPENSSL" in hint or "OpenSSL" in hint or "SECLEVEL" in hint
