"""Multi-fidelity cascade: Stage A L1 → Stage B L3 on elites (mocked L3)."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

import pytest

from yard_sea_v0.hull import HullState
from yard_sea_v0.multifidelity import (
    COST_AWARE_NOTES,
    COST_L1,
    COST_L3,
    FIDELITY_L1,
    run_multifidelity_search,
    select_elites,
    stage_a_score,
    stage_b_score,
)
from yard_sea_v0.search import botorch_available
from yard_sea_v0.teachers.openfoam_l3 import FIDELITY_RANS, OpenFOAMAvailability


def _fake_l3(stl_path, Fn, case_dir, **kwargs):
    name = Path(stl_path).stem
    digits = "".join(ch for ch in name if ch.isdigit()) or "0"
    bump = 0.01 * int(digits)
    cd = 0.12 + bump
    return {
        "Fn": float(Fn),
        "Rn": 1e7,
        "Cf": float("nan"),
        "k1": float("nan"),
        "Cw": float("nan"),
        "Rt_N": 1e5,
        "Ct": cd,
        "fidelity": FIDELITY_RANS,
        "notes": "mock L3_rans",
        "skipped": False,
        "skip_reason": None,
        "Cd": cd,
        "Cl": -0.1,
        "Cm": 0.0,
        "teacher": "openfoam_l3",
        "solver": "simpleFoam",
        "force_coeffs": {"Cd": cd, "Cl": -0.1, "Cm": 0.0},
    }


def test_select_elites_top_k_by_stage_a():
    rows = [
        {"hull": {"L": 1}, "ct": 0.05, "skipped": False},
        {"hull": {"L": 1}, "ct": 0.01, "skipped": False},
        {"hull": {"L": 1}, "ct": 0.03, "skipped": False},
        {"skipped": True, "ct": 0.001},
    ]
    idx = select_elites(rows, 2)
    assert idx == [1, 2]


def test_run_multifidelity_mocked_l3(tmp_path: Path):
    avail = OpenFOAMAvailability(foam_bin="/usr/bin/simpleFoam", docker=True)
    out = run_multifidelity_search(
        [HullState()],
        steps=3,
        seed=0,
        use_botorch=False,
        use_l15=False,
        l3_top=1,
        cost_aware=False,
        out_dir=tmp_path,
        l3_runner=_fake_l3,
        l3_availability=avail,
    )
    results = out["results"]
    summary = out["summary"]
    assert summary["multifidelity"] is True
    assert summary["n_l3_evaluated"] == 1
    assert len(out["elite_indices"]) == 1
    elite_i = out["elite_indices"][0]
    elite = results[elite_i]
    assert elite["l3_elite"] is True
    assert elite["Cd"] is not None
    assert elite["l3_fidelity"] == FIDELITY_RANS
    levels = [s["level"] for s in elite["fidelity_ladder"]]
    assert FIDELITY_L1 in levels
    assert any(str(lv).startswith("L3") for lv in levels)
    assert any(s.get("Cd") is not None for s in elite["fidelity_ladder"])
    for i, r in enumerate(results):
        if i == elite_i:
            continue
        assert r.get("l3_elite") is False
        assert any(
            s.get("skip_reason") == "not_elite_cost_gate"
            for s in (r.get("fidelity_ladder") or [])
        )


def test_gallery_multifidelity_records_ladder(tmp_path: Path):
    from yard_sea_v0.gallery import write_gallery

    avail = OpenFOAMAvailability(foam_bin="/usr/bin/simpleFoam", docker=True)

    def _mf_with_mock(*args, **kwargs):
        kwargs = dict(kwargs)
        kwargs["l3_runner"] = _fake_l3
        kwargs["l3_availability"] = avail
        kwargs.setdefault("skip_l3", False)
        return run_multifidelity_search(*args, **kwargs)

    with patch("yard_sea_v0.multifidelity.run_multifidelity_search", side_effect=_mf_with_mock):
        # gallery imports run_multifidelity_search inside the function — patch gallery binding
        with patch("yard_sea_v0.gallery.detect_openfoam", return_value=avail):
            # Re-patch at the point of use: write_gallery does local import
            import yard_sea_v0.multifidelity as mf_mod

            with patch.object(mf_mod, "run_multifidelity_search", side_effect=_mf_with_mock):
                # Actually write_gallery imports the symbol — patch via injecting through
                # a wrapper on the gallery module after import site. Simpler: call
                # write_gallery but monkeypatch evaluate path by patching openfoam run_teacher.
                pass

    with (
        patch("yard_sea_v0.teachers.openfoam_l3.detect_openfoam", return_value=avail),
        patch("yard_sea_v0.teachers.openfoam_l3.run_teacher", side_effect=_fake_l3),
        patch("yard_sea_v0.gallery.detect_openfoam", return_value=avail),
    ):
        manifest = write_gallery(
            tmp_path,
            n_parents=1,
            steps=2,
            seed=0,
            multifidelity=True,
            l3_top=1,
            use_botorch=False,
            cost_aware=False,
        )
    assert manifest["multifidelity"] is True
    assert manifest["l3_top"] == 1
    assert manifest["multifidelity_summary"]["n_l3_evaluated"] == 1
    children = list((tmp_path / "children").glob("child_*.json"))
    assert len(children) >= 2
    elite_found = False
    for p in children:
        child = json.loads(p.read_text())
        assert "fidelity_ladder" in child
        assert isinstance(child["fidelity_ladder"], list)
        assert child["fidelity_ladder"][0]["level"] == FIDELITY_L1
        if child.get("l3_elite"):
            elite_found = True
            assert child.get("Cd") is not None
    assert elite_found


def test_cli_multifidelity_flags(tmp_path: Path):
    from yard_sea_v0.cli import main

    avail = OpenFOAMAvailability(foam_bin="/usr/bin/simpleFoam", docker=True)
    with (
        patch("yard_sea_v0.teachers.openfoam_l3.detect_openfoam", return_value=avail),
        patch("yard_sea_v0.teachers.openfoam_l3.run_teacher", side_effect=_fake_l3),
        patch("yard_sea_v0.gallery.detect_openfoam", return_value=avail),
    ):
        rc = main(
            [
                "run-search",
                "--multifidelity",
                "--l3-top",
                "1",
                "--parents",
                "1",
                "--steps",
                "2",
                "--seed",
                "0",
                "--out",
                str(tmp_path / "gal"),
            ]
        )
    assert rc == 0
    manifest = json.loads((tmp_path / "gal" / "manifest.json").read_text())
    assert manifest["multifidelity"] is True
    assert manifest["l3_top"] == 1


def test_stage_b_prefers_cd():
    accepted = {"passed": True, "failed_checks": []}
    row = {"ct": 0.05, "Cd": 0.2, "l3_openfoam": {"Cd": 0.2, "Ct": 0.21, "acceptance": accepted}}
    assert stage_b_score(row) == 0.2
    assert stage_a_score(row) == 0.05


def test_stage_b_does_not_credit_unaccepted_l3():
    """An L3 Cd without a passing acceptance gate falls back to the Stage-A score."""
    no_gate = {"ct": 0.05, "Cd": 0.2, "l3_openfoam": {"Cd": 0.2, "Ct": 0.21}}
    assert stage_b_score(no_gate) == 0.05
    failed = {
        "ct": 0.05,
        "Cd": 0.2,
        "l3_openfoam": {"Cd": 0.2, "acceptance": {"passed": False, "failed_checks": ["Cl_settled"]}},
    }
    assert stage_b_score(failed) == 0.05


@pytest.mark.skipif(not botorch_available(), reason="botorch/torch not installed")
def test_multifidelity_botorch_cost_aware_smoke(tmp_path: Path):
    avail = OpenFOAMAvailability(foam_bin="/usr/bin/simpleFoam", docker=True)
    out = run_multifidelity_search(
        [HullState()],
        steps=3,
        seed=1,
        use_botorch=True,
        use_l15=False,
        l3_top=1,
        cost_aware=True,
        out_dir=tmp_path,
        l3_runner=_fake_l3,
        l3_availability=avail,
    )
    methods = {r.get("method") for r in out["results"]}
    assert "botorch_mf" in methods or "botorch" in methods
    bo = next(r for r in out["results"] if str(r.get("method", "")).startswith("botorch"))
    if not bo.get("skipped"):
        assert bo.get("cost_aware") is True
        assert "Cost-aware approximation" in (bo.get("cost_aware_notes") or COST_AWARE_NOTES)
    assert out["summary"]["n_l3_evaluated"] == 1
    assert out["summary"]["total_cost_units"] >= COST_L1
