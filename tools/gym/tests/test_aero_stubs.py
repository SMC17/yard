"""Tests for Strip-path aero oracle stubs (OpenVSP / NeuralFoil / JSBSim)."""

from __future__ import annotations

from unittest.mock import patch

import pytest

from yard_sea_v0.teachers import jsbsim_stub, neuralfoil_stub, openvsp_stub


def test_openvsp_detect_and_skip():
    avail = openvsp_stub.detect()
    d = avail.to_dict()
    assert "available" in d
    assert "install_hint" in d
    # Force unavailable path
    fake = openvsp_stub.OpenVSPAvailability()
    r = openvsp_stub.run(availability=fake)
    assert r["skipped"] is True
    assert r["skip_reason"] == "openvsp_unavailable"
    assert r["fidelity"] == openvsp_stub.FIDELITY_PENDING
    assert r["teacher"] == "openvsp_stub"


def test_openvsp_skip_even_when_detected_adapter_pending():
    fake = openvsp_stub.OpenVSPAvailability(vsp_bin="/usr/bin/vsp", python_mod=True)
    r = openvsp_stub.run(availability=fake)
    assert r["skipped"] is True
    assert r["skip_reason"] == "openvsp_adapter_pending"


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
    assert "Teacher protocol" in (teachers.__doc__ or "")
