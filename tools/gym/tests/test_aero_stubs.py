"""Tests for Strip-path aero oracle stubs (OpenVSP / NeuralFoil / JSBSim / VSPAERO)."""

from __future__ import annotations

from pathlib import Path

import pytest

from yard_sea_v0.teachers import jsbsim_stub, neuralfoil_stub, openvsp_stub, vspaero_l1


def test_openvsp_detect_and_skip():
    avail = openvsp_stub.detect()
    d = avail.to_dict()
    assert "available" in d
    assert "install_hint" in d
    assert "vspaero" in d
    # Force unavailable path
    fake = openvsp_stub.OpenVSPAvailability()
    r = openvsp_stub.run(availability=fake)
    assert r["skipped"] is True
    assert r["skip_reason"] == "openvsp_unavailable"
    assert r["fidelity"] == openvsp_stub.FIDELITY_PENDING
    assert r["teacher"] == "openvsp_stub"


def test_openvsp_thin_call_when_cli_available(tmp_path):
    avail = openvsp_stub.detect()
    if not avail.vsp_bin:
        pytest.skip("OpenVSP CLI not installed (vendor/openvsp or PATH)")
    r = openvsp_stub.run(availability=avail, work_dir=str(tmp_path), alpha_deg=2.0)
    assert r["skipped"] is False
    assert r["fidelity"] == openvsp_stub.FIDELITY
    assert r["skip_reason"] is None
    # With vspaero present, expect real coeffs; else geometry-only None
    if avail.vspaero:
        assert r["CL"] is not None and abs(r["CL"]) > 0.01
        assert r["CD"] is not None and r["CD"] > 0
        assert r["CM"] is not None
        assert (tmp_path / "yard_sea_vspaero.vsp3").is_file()
    else:
        assert r["CL"] is None
        assert (tmp_path / "yard_sea_smoke.vsp3").is_file()


def test_openvsp_cli_missing_with_python_only():
    fake = openvsp_stub.OpenVSPAvailability(vsp_bin=None, python_mod=True)
    r = openvsp_stub.run(availability=fake)
    assert r["skipped"] is True
    assert r["skip_reason"] == "openvsp_cli_missing"


def test_vspaero_detect_and_skip():
    avail = vspaero_l1.detect()
    d = avail.to_dict()
    assert "available" in d
    assert "install_hint" in d
    fake = vspaero_l1.VSPAEROAvailability()
    r = vspaero_l1.run(availability=fake)
    assert r["skipped"] is True
    assert r["skip_reason"] == "vspaero_unavailable"
    assert r["fidelity"] == vspaero_l1.FIDELITY_PENDING


def test_vspaero_parse_markers():
    text = "yard_sea_CL=0.182078\nyard_sea_CD=0.00629931\nyard_sea_CM=-0.0411911\n"
    m = vspaero_l1.parse_markers(text)
    assert m["CL"] == pytest.approx(0.182078)
    assert m["CD"] == pytest.approx(0.00629931)
    assert m["CM"] == pytest.approx(-0.0411911)


def test_vspaero_parse_polar(tmp_path):
    polar = tmp_path / "yard_sea_vspaero.polar"
    polar.write_text(
        "\n".join(
            [
                "header junk",
                "      Beta             Mach             AoA             Re/1e6             CLo             CLi            CLtot              CDo              CDi             CDtot              CSo              CSi            CStot               L/D              E               CMox             CMoy             CMoz             CMix             CMiy             CMiz             CMxtot           CMytot           CMztot",
                "  0.000000000000   0.100000000000   2.000000000000  10.000000000000  -0.000188046132   0.182265973011   0.182077926879   0.005384936665   0.000914368647   0.006299305313   0.0 0.0 0.0 28.9 0.96 0.0 0.0 0.0 0.0 -0.041191086938 0.0 0.0 -0.041191086938 0.0",
            ]
        ),
        encoding="utf-8",
    )
    m = vspaero_l1.parse_polar(polar)
    assert m["CL"] == pytest.approx(0.182077926879)
    assert m["CD"] == pytest.approx(0.006299305313)
    assert m["CM"] == pytest.approx(-0.041191086938)


def test_vspaero_thin_wing_when_available(tmp_path):
    avail = vspaero_l1.detect()
    if not avail.available:
        pytest.skip("vspscript/vspaero not installed under vendor/openvsp")
    r = vspaero_l1.run(availability=avail, work_dir=str(tmp_path), alpha_deg=2.0)
    assert r["skipped"] is False
    assert r["fidelity"] == vspaero_l1.FIDELITY
    assert r["CL"] is not None and abs(r["CL"]) > 0.05
    assert r["CD"] is not None and 0 < r["CD"] < 0.1
    assert r["CM"] is not None
    assert (tmp_path / "yard_sea_vspaero.vsp3").is_file()
    assert (tmp_path / "yard_sea_vspaero.polar").is_file()


def test_neuralfoil_skip_when_unavailable():
    fake = neuralfoil_stub.NeuralFoilAvailability()
    r = neuralfoil_stub.run(availability=fake)
    assert r["skipped"] is True
    assert r["skip_reason"] == "neuralfoil_unavailable"
    assert r["fidelity"] == neuralfoil_stub.FIDELITY_PENDING


def test_neuralfoil_detect_and_thin_call_if_installed():
    avail = neuralfoil_stub.detect()
    assert "install_hint" in avail.to_dict()
    if not avail.available:
        pytest.skip("neuralfoil not installed")
    r = neuralfoil_stub.run(alpha_deg=2.0, Re=1e6, model_size="small")
    assert r["skipped"] is False
    assert r["fidelity"] == neuralfoil_stub.FIDELITY
    assert r["CL"] is not None and abs(r["CL"]) > 0
    assert r["CD"] is not None and r["CD"] > 0


def test_jsbsim_skip_when_unavailable():
    fake = jsbsim_stub.JSBSimAvailability()
    r = jsbsim_stub.run(availability=fake)
    assert r["skipped"] is True
    assert r["skip_reason"] == "jsbsim_unavailable"
    assert r["fidelity"] == jsbsim_stub.FIDELITY_PENDING


def test_jsbsim_detect_and_thin_call_if_installed():
    avail = jsbsim_stub.detect()
    assert "install_hint" in avail.to_dict()
    if not avail.available:
        pytest.skip("jsbsim not installed")
    r = jsbsim_stub.run(model="c172x", n_steps=5)
    assert r["skipped"] is False
    assert r["fidelity"] == jsbsim_stub.FIDELITY
    assert r["sim_time_sec"] is not None and r["sim_time_sec"] > 0
    assert r["vt_fps"] is not None and r["vt_fps"] > 0


def test_teacher_protocol_exports():
    from yard_sea_v0 import teachers

    assert hasattr(teachers, "openvsp_stub")
    assert hasattr(teachers, "neuralfoil_stub")
    assert hasattr(teachers, "jsbsim_stub")
    assert hasattr(teachers, "michell_l15")
    assert hasattr(teachers, "vspaero_l1")
    assert "Teacher protocol" in (teachers.__doc__ or "")


def test_jsbsim_run_writes_nothing_to_cwd(tmp_path, monkeypatch):
    if not jsbsim_stub.detect().available:
        pytest.skip("jsbsim not installed")
    monkeypatch.chdir(tmp_path)
    r = jsbsim_stub.run()
    assert r["skipped"] is False
    assert list(tmp_path.iterdir()) == []  # model <output> directives must not land in cwd
