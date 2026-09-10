"""Mock L3_rans forceCoeffs teacher → Cd recorded in gallery child JSON."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

from yard_sea_v0.gallery import write_gallery
from yard_sea_v0.teachers.openfoam_l3 import (
    FIDELITY_PENDING,
    FIDELITY_RANS,
    OpenFOAMAvailability,
)


def _fake_l3_rans(*args, **kwargs):
    return {
        "Fn": 0.2,
        "Rn": 1e7,
        "Cf": float("nan"),
        "k1": float("nan"),
        "Cw": float("nan"),
        "Rt_N": 1.2e5,
        "Ct": 0.1459,
        "fidelity": FIDELITY_RANS,
        "notes": "mock L3_rans",
        "skipped": False,
        "skip_reason": None,
        "Cd": 0.1459,
        "Cl": -0.175,
        "Cm": 0.0494,
        "teacher": "openfoam_l3",
        "solver": "simpleFoam",
        "force_coeffs": {"Cd": 0.1459, "Cl": -0.175, "Cm": 0.0494},
    }


def test_gallery_records_l3_cd_with_mock_teacher(tmp_path: Path):
    avail = OpenFOAMAvailability(foam_bin="/usr/bin/simpleFoam", docker=True)
    with (
        patch("yard_sea_v0.gallery.detect_openfoam", return_value=avail),
        patch("yard_sea_v0.gallery.run_teacher", side_effect=_fake_l3_rans),
    ):
        manifest = write_gallery(
            tmp_path,
            n_parents=1,
            steps=2,
            seed=0,
            l3_openfoam=True,
            use_botorch=False,
        )
    assert manifest["l3_openfoam"] is True
    assert len(manifest["l3_summaries"]) >= 1
    for s in manifest["l3_summaries"]:
        assert s["fidelity"] == FIDELITY_RANS
        assert s["Cd"] == 0.1459
        assert s["solver"] == "simpleFoam"
        assert s["skipped"] is False

    child = json.loads((tmp_path / "children" / "child_000.json").read_text())
    assert child["Cd"] == 0.1459
    assert child["l3_fidelity"] == FIDELITY_RANS
    assert child["l3_Ct"] == 0.1459
    assert child["l3_solver"] == "simpleFoam"
    assert child["l3_openfoam"]["fidelity"] == FIDELITY_RANS
    assert child["l3_openfoam"]["Cd"] == 0.1459


def test_gallery_l3_pending_still_records_null_cd(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("YARD_SEA_L3_SKIP_SOLVE", "1")
    fake = OpenFOAMAvailability()
    with patch("yard_sea_v0.gallery.detect_openfoam", return_value=fake):
        manifest = write_gallery(
            tmp_path,
            n_parents=1,
            steps=2,
            seed=0,
            l3_openfoam=True,
            use_botorch=False,
        )
    assert manifest["l3_summaries"]
    # Without FOAM, teacher returns pending / skipped; Cd may be None.
    for s in manifest["l3_summaries"]:
        assert s["fidelity"] in (FIDELITY_PENDING, FIDELITY_RANS)
    child = json.loads((tmp_path / "children" / "child_000.json").read_text())
    assert "l3_openfoam" in child
    assert "Cd" in child  # key present even if null
