"""OpenVSP geometry/aero oracle stub (Strip air path).

``detect()`` probes PATH and ``vendor/openvsp/{vspscript,vsp}``.
``run()`` prefers real VSPAERO CL/CD/CM via ``teachers.vspaero_l1`` (thin wing
through ``VSPAEROComputeGeometry`` + ``VSPAEROSweep``). If VSPAERO binaries are
missing but ``vspscript`` is present, falls back to a POD-only geometry smoke.

Not certification, not operational.

Install: see ``docs/OPENVSP_INSTALL.md`` (Ubuntu .deb extract into vendor/).
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from . import binprobe

FIDELITY_PENDING = "aero_openvsp_pending"
FIDELITY = "aero_openvsp"
TEACHER = "openvsp_stub"

_REPO_ROOT = Path(__file__).resolve().parents[2]
_VENDOR_OPENVSP = _REPO_ROOT / "vendor" / "openvsp"

_MINIMAL_SCRIPT = """void main()
{
    Print( string( "yard_sea_openvsp_smoke_ok" ) );
    ClearVSPModel();
    Update();

    string pid = AddGeom( "POD", "" );
    SetParmVal( pid, "Length", "Design", 1.0 );
    Update();

    Print( string( "yard_sea_pod_id=" ) + pid );

    WriteVSPFile( "yard_sea_smoke.vsp3", SET_ALL );
    Print( string( "yard_sea_wrote_vsp3" ) );

    while ( GetNumTotalErrors() > 0 )
    {
        ErrorObj err = PopLastError();
        Print( err.GetErrorString() );
    }
}
"""


@dataclass
class OpenVSPAvailability:
    vsp_bin: str | None = None
    vspaero: str | None = None
    python_mod: bool = False
    version: str | None = None
    load_error: str | None = None

    @property
    def available(self) -> bool:
        return bool(self.vsp_bin) or self.python_mod

    def to_dict(self) -> dict[str, Any]:
        return {
            "vsp_bin": self.vsp_bin,
            "vspaero": self.vspaero,
            "python_mod": self.python_mod,
            "version": self.version,
            "load_error": self.load_error,
            "available": self.available,
            "install_hint": (
                "Prefer vendor/openvsp from Ubuntu .deb extract "
                "(docs/OPENVSP_INSTALL.md). Or install OpenVSP from "
                "https://openvsp.org/ and put vspscript/vsp on PATH. "
                "No lightweight apt/pip package on Debian."
            ),
        }


def _candidate_bins() -> list[Path]:
    names = ("vspscript", "vsp")
    out: list[Path] = []
    for name in names:
        p = _VENDOR_OPENVSP / name
        if p.is_file() and os.access(p, os.X_OK):
            out.append(p)
        which = shutil.which(name)
        if which:
            out.append(Path(which))
    # de-dupe preserving order
    seen: set[str] = set()
    uniq: list[Path] = []
    for p in out:
        key = str(p.resolve()) if p.exists() else str(p)
        if key not in seen:
            seen.add(key)
            uniq.append(p)
    return uniq


def _find_vspaero() -> str | None:
    p = _VENDOR_OPENVSP / "vspaero"
    if p.is_file() and os.access(p, os.X_OK):
        return str(p)
    which = shutil.which("vspaero")
    return which


def detect() -> OpenVSPAvailability:
    """Probe PATH / vendor / import for OpenVSP; binaries must actually load."""
    vsp_bin: str | None = None
    for cand in _candidate_bins():
        # Prefer vspscript for headless scripting
        if cand.name == "vspscript":
            vsp_bin = str(cand)
            break
    if vsp_bin is None and _candidate_bins():
        vsp_bin = str(_candidate_bins()[0])

    python_mod = False
    version = None
    try:
        import openvsp as vsp  # type: ignore

        python_mod = True
        version = getattr(vsp, "GetVSPVersion", lambda: None)() or getattr(
            vsp, "__version__", None
        )
        if callable(version):
            try:
                version = version()
            except Exception:
                version = str(version)
    except Exception:
        python_mod = False

    # Existence is not availability: drop binaries the loader cannot start
    # (e.g. vendored .deb extract missing libcminpack.so.1).
    errs: list[str] = []
    if vsp_bin:
        pr = binprobe.probe(vsp_bin)
        if not pr.ok:
            errs.append(f"{Path(vsp_bin).name}:{pr.reason}")
            vsp_bin = None
    vspaero = _find_vspaero()
    if vspaero:
        pr = binprobe.probe(vspaero)
        if not pr.ok:
            errs.append(f"vspaero:{pr.reason}")
            vspaero = None

    if version is None and vsp_bin:
        version = "cli"

    return OpenVSPAvailability(
        vsp_bin=vsp_bin,
        vspaero=vspaero,
        python_mod=python_mod,
        version=version,
        load_error="; ".join(errs) or None,
    )


def _run_vspscript(bin_path: str, work: Path) -> dict[str, Any]:
    work = work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    script_path = work / "yard_sea_minimal.vspscript"
    script_path.write_text(_MINIMAL_SCRIPT, encoding="utf-8")
    out_vsp3 = work / "yard_sea_smoke.vsp3"

    # vspscript may abort on teardown (nonzero) after successful WriteVSPFile.
    # Pass script basename only (relative path-as-module breaks GetModule).
    proc = subprocess.run(
        [bin_path, "-script", script_path.name],
        cwd=str(work),
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
    ok_marker = "yard_sea_openvsp_smoke_ok" in combined
    wrote = out_vsp3.is_file() and out_vsp3.stat().st_size > 0
    compile_err = "Error ExecuteScript" in combined or " : ERR  :" in combined

    return {
        "returncode": proc.returncode,
        "stdout": proc.stdout or "",
        "stderr": proc.stderr or "",
        "ok_marker": ok_marker,
        "wrote_vsp3": wrote,
        "vsp3_path": str(out_vsp3) if wrote else None,
        "vsp3_bytes": out_vsp3.stat().st_size if wrote else 0,
        "compile_err": compile_err,
        "success": bool(ok_marker and wrote and not compile_err),
    }


def run(
    *,
    model_path: str | None = None,
    alpha_deg: float = 2.0,
    availability: OpenVSPAvailability | None = None,
    work_dir: str | None = None,
) -> dict[str, Any]:
    """OpenVSP teacher: prefer VSPAERO CL/CD/CM; else POD geometry smoke.

    When ``vspaero`` is available beside ``vspscript``, delegates to
    ``vspaero_l1.run()`` for real vortex-lattice coefficients. Otherwise
    runs the thin POD ``WriteVSPFile`` vehicle (CL/CD/CM remain None).
    """
    avail = availability if availability is not None else detect()
    if not avail.available:
        return {
            "teacher": TEACHER,
            "skipped": True,
            "skip_reason": "openvsp_unavailable",
            "fidelity": FIDELITY_PENDING,
            "CL": None,
            "CD": None,
            "CM": None,
            "alpha_deg": alpha_deg,
            "model_path": model_path,
            "availability": avail.to_dict(),
            "notes": (
                "OpenVSP oracle stub — binary/bindings absent. "
                "Not cert / not operational."
            ),
        }

    # Prefer real VSPAERO when both vspscript and vspaero are present.
    try:
        from . import vspaero_l1
    except ImportError:
        vspaero_l1 = None  # type: ignore

    if vspaero_l1 is not None and avail.vsp_bin and avail.vspaero:
        va = vspaero_l1.VSPAEROAvailability(
            vspscript=avail.vsp_bin
            if Path(avail.vsp_bin).name == "vspscript"
            else None,
            vspaero=avail.vspaero,
            version=avail.version,
        )
        if va.vspscript is None:
            # detect() may have picked plain `vsp`; prefer vspscript for scripts
            for cand in _candidate_bins():
                if cand.name == "vspscript":
                    va.vspscript = str(cand)
                    break
        if va.available:
            vr = vspaero_l1.run(
                alpha_deg=alpha_deg,
                availability=va,
                work_dir=work_dir,
                model_path=model_path,
            )
            if not vr.get("skipped"):
                return {
                    "teacher": TEACHER,
                    "skipped": False,
                    "skip_reason": None,
                    "fidelity": FIDELITY,
                    "CL": vr["CL"],
                    "CD": vr["CD"],
                    "CM": vr["CM"],
                    "alpha_deg": alpha_deg,
                    "model_path": model_path,
                    "availability": avail.to_dict(),
                    "cli": vr.get("cli"),
                    "vspaero_teacher": vr.get("teacher"),
                    "notes": (
                        "OpenVSP + VSPAERO thin wing OK "
                        f"(CL={vr['CL']}, CD={vr['CD']}, CM={vr['CM']} @ "
                        f"alpha={alpha_deg} deg). "
                        "Not cert / not operational."
                    ),
                }
            # VSPAERO failed — fall through to geometry-only smoke

    bin_path = avail.vsp_bin
    if not bin_path:
        return {
            "teacher": TEACHER,
            "skipped": True,
            "skip_reason": "openvsp_cli_missing",
            "fidelity": FIDELITY_PENDING,
            "CL": None,
            "CD": None,
            "CM": None,
            "alpha_deg": alpha_deg,
            "model_path": model_path,
            "availability": avail.to_dict(),
            "notes": (
                "Python openvsp present but no vspscript/vsp CLI for thin call. "
                "Not cert / not operational."
            ),
        }

    # Prefer vspscript even if detect picked vsp
    vspscript = None
    for cand in _candidate_bins():
        if cand.name == "vspscript":
            vspscript = str(cand)
            break
    if vspscript:
        bin_path = vspscript

    try:
        if work_dir:
            work = Path(work_dir)
            work.mkdir(parents=True, exist_ok=True)
            detail = _run_vspscript(bin_path, work)
        else:
            with tempfile.TemporaryDirectory(prefix="yard_openvsp_") as td:
                detail = _run_vspscript(bin_path, Path(td))
    except subprocess.TimeoutExpired:
        return {
            "teacher": TEACHER,
            "skipped": True,
            "skip_reason": "openvsp_timeout",
            "fidelity": FIDELITY_PENDING,
            "CL": None,
            "CD": None,
            "CM": None,
            "alpha_deg": alpha_deg,
            "model_path": model_path,
            "availability": avail.to_dict(),
            "notes": "vspscript timed out. Not cert / not operational.",
        }
    except Exception as exc:
        return {
            "teacher": TEACHER,
            "skipped": True,
            "skip_reason": f"run_error:{type(exc).__name__}",
            "fidelity": FIDELITY_PENDING,
            "CL": None,
            "CD": None,
            "CM": None,
            "alpha_deg": alpha_deg,
            "model_path": model_path,
            "availability": avail.to_dict(),
            "notes": f"OpenVSP thin call failed: {exc}. Not cert / not operational.",
        }

    if not detail["success"]:
        return {
            "teacher": TEACHER,
            "skipped": True,
            "skip_reason": "openvsp_script_failed",
            "fidelity": FIDELITY_PENDING,
            "CL": None,
            "CD": None,
            "CM": None,
            "alpha_deg": alpha_deg,
            "model_path": model_path,
            "availability": avail.to_dict(),
            "cli": {
                "bin": bin_path,
                "returncode": detail["returncode"],
                "compile_err": detail["compile_err"],
                "ok_marker": detail["ok_marker"],
                "wrote_vsp3": detail["wrote_vsp3"],
            },
            "notes": (
                "vspscript ran but thin vehicle script did not succeed. "
                "Not cert / not operational."
            ),
        }

    return {
        "teacher": TEACHER,
        "skipped": False,
        "skip_reason": None,
        "fidelity": FIDELITY,
        "CL": None,
        "CD": None,
        "CM": None,
        "alpha_deg": alpha_deg,
        "model_path": model_path,
        "availability": avail.to_dict(),
        "cli": {
            "bin": bin_path,
            "returncode": detail["returncode"],
            "vsp3_bytes": detail["vsp3_bytes"],
            "note": (
                "Geometry-only fallback (VSPAERO unavailable or failed). "
                "vspscript often exits nonzero after successful WriteVSPFile."
            ),
        },
        "notes": (
            "OpenVSP thin geometry call OK (ClearVSPModel + POD + WriteVSPFile). "
            "VSPAERO CL/CD/CM not available on this run. Not cert / not operational."
        ),
    }


def run_teacher(**kwargs: Any) -> dict[str, Any]:
    return run(**kwargs)
