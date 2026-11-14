"""Binary load probe: existence on disk is not availability."""

from __future__ import annotations

import os
import stat
from pathlib import Path

from yard_sea_v0.teachers import binprobe, openvsp_stub, vspaero_l1


def _script(tmp_path: Path, name: str, body: str) -> Path:
    p = tmp_path / name
    p.write_text("#!/bin/sh\n" + body + "\n")
    p.chmod(p.stat().st_mode | stat.S_IXUSR)
    return p


def test_probe_missing():
    assert binprobe.probe(None).ok is False
    assert binprobe.probe("/nonexistent/vspaero").reason == "missing"


def test_probe_ok(tmp_path):
    binprobe.clear_cache()
    p = _script(tmp_path, "fine", "echo usage; exit 1")
    r = binprobe.probe(p)
    assert r.ok is True and r.reason is None


def test_probe_loader_error(tmp_path):
    binprobe.clear_cache()
    p = _script(
        tmp_path,
        "broken",
        "echo 'broken: error while loading shared libraries: libcminpack.so.1: "
        "cannot open shared object file: No such file or directory' >&2; exit 127",
    )
    r = binprobe.probe(p)
    assert r.ok is False
    assert "libcminpack" in (r.reason or "")


def test_probe_exit_127(tmp_path):
    binprobe.clear_cache()
    p = _script(tmp_path, "gone", "exit 127")
    assert binprobe.probe(p).ok is False


def test_vspaero_detect_rejects_unloadable(tmp_path, monkeypatch):
    binprobe.clear_cache()
    bad = "echo 'x: error while loading shared libraries: libfoo.so' >&2; exit 127"
    vs = _script(tmp_path, "vspscript", bad)
    va = _script(tmp_path, "vspaero", bad)
    monkeypatch.setattr(vspaero_l1, "_VENDOR_OPENVSP", tmp_path)
    avail = vspaero_l1.detect()
    assert avail.vspscript == str(vs) and avail.vspaero == str(va)
    assert avail.loads is False
    assert avail.available is False
    assert "libfoo" in (avail.load_error or "")
    r = vspaero_l1.run(availability=avail)
    assert r["skipped"] is True
    assert r["skip_reason"] == "vspaero_binary_load_failed"


def test_openvsp_detect_drops_unloadable(tmp_path, monkeypatch):
    binprobe.clear_cache()
    bad = "echo 'x: error while loading shared libraries: libfoo.so' >&2; exit 127"
    _script(tmp_path, "vspscript", bad)
    _script(tmp_path, "vspaero", bad)
    monkeypatch.setattr(openvsp_stub, "_VENDOR_OPENVSP", tmp_path)
    monkeypatch.setenv("PATH", str(tmp_path / "empty"))
    avail = openvsp_stub.detect()
    assert avail.vsp_bin is None
    assert avail.vspaero is None
    assert avail.load_error and "libfoo" in avail.load_error


def test_handbuilt_availability_unprobed():
    # Hand-built availability (loads=None) keeps the old semantics for tests.
    a = vspaero_l1.VSPAEROAvailability(vspscript="/x", vspaero="/y")
    assert a.available is True
