"""VSPAERO L1 aero teacher (OpenVSP Strip air path).

Runs a thin rectangular wing through ``vspscript`` analyses:

1. ``VSPAEROComputeGeometry``
2. ``VSPAEROSweep`` (single alpha)

Parses printed markers (``yard_sea_CL=…``) and optionally ``*.polar``.

Requires vendored OpenVSP CLI (``vspscript`` + ``vspaero``) under
``vendor/openvsp`` — see ``docs/OPENVSP_INSTALL.md``.

Fidelity: exploratory vortex-lattice ranking only.
Not certification, not operational, not FAA / class.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from . import binprobe

FIDELITY_PENDING = "aero_vspaero_pending"
FIDELITY = "aero_vspaero_l1"
TEACHER = "vspaero_l1"

_REPO_ROOT = Path(__file__).resolve().parents[2]
_VENDOR_OPENVSP = _REPO_ROOT / "vendor" / "openvsp"

_MARKER_RE = re.compile(
    r"yard_sea_(CL|CD|CM)=([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)"
)

# AngelScript: thin wing + VSPAEROComputeGeometry + single-point VSPAEROSweep.
# ALPHA_PLACEHOLDER is replaced with the requested alpha (degrees).
_VSPAERO_SCRIPT = r"""void main()
{
    Print( string( "yard_sea_vspaero_start" ) );
    ClearVSPModel();
    Update();

    string wing_id = AddGeom( "WING", "" );
    SetGeomName( wing_id, "YardWing" );

    SetDriverGroup( wing_id, 1, AREA_WSECT_DRIVER, ROOTC_WSECT_DRIVER, TIPC_WSECT_DRIVER );
    SetParmVal( wing_id, "Root_Chord", "XSec_1", 1.0 );
    SetParmVal( wing_id, "Tip_Chord", "XSec_1", 1.0 );
    SetParmVal( wing_id, "Area", "XSec_1", 6.0 );
    SetParmVal( wing_id, "Sweep", "XSec_1", 0.0 );
    SetParmVal( wing_id, "Tess_W", "Shape", 33 );
    SetParmVal( wing_id, "SectTess_U", "XSec_1", 8 );
    Update();

    WriteVSPFile( "yard_sea_vspaero.vsp3", SET_ALL );
    ClearVSPModel();
    Update();
    ReadVSPFile( "yard_sea_vspaero.vsp3" );
    Update();

    string compgeom_name = "VSPAEROComputeGeometry";
    SetAnalysisInputDefaults( compgeom_name );
    Print( string( "yard_sea_compgeom_exec" ) );
    string compgeom_resid = ExecAnalysis( compgeom_name );
    Print( string( "yard_sea_compgeom_done" ) );

    string analysis_name = "VSPAEROSweep";
    SetAnalysisInputDefaults( analysis_name );

    array<int> geom_set;
    geom_set.push_back( 0 );
    SetIntAnalysisInput( analysis_name, "GeomSet", geom_set, 0 );

    array<int> ref_flag;
    ref_flag.push_back( 1 );
    SetIntAnalysisInput( analysis_name, "RefFlag", ref_flag, 0 );

    array<string> wid = FindGeomsWithName( "YardWing" );
    if ( wid.length() == 0 )
    {
        wid = FindGeomsWithName( "WingGeom" );
    }
    if ( wid.length() > 0 )
    {
        SetStringAnalysisInput( analysis_name, "WingID", wid, 0 );
    }

    array<double> alpha;
    alpha.push_back( ALPHA_PLACEHOLDER );
    SetDoubleAnalysisInput( analysis_name, "AlphaStart", alpha, 0 );
    array<int> alphaNpts;
    alphaNpts.push_back( 1 );
    SetIntAnalysisInput( analysis_name, "AlphaNpts", alphaNpts, 0 );

    array<double> mach;
    mach.push_back( 0.1 );
    SetDoubleAnalysisInput( analysis_name, "MachStart", mach, 0 );
    array<int> machNpts;
    machNpts.push_back( 1 );
    SetIntAnalysisInput( analysis_name, "MachNpts", machNpts, 0 );

    array<int> ncpu;
    ncpu.push_back( 1 );
    SetIntAnalysisInput( analysis_name, "NCPU", ncpu, 0 );

    array<int> wakeIters;
    wakeIters.push_back( 3 );
    SetIntAnalysisInput( analysis_name, "WakeNumIter", wakeIters, 0 );

    Update();
    Print( string( "yard_sea_sweep_exec" ) );
    string rid = ExecAnalysis( analysis_name );
    Print( string( "yard_sea_sweep_done" ) );

    string history_res = FindLatestResultsID( "VSPAERO_History" );
    Print( string( "yard_sea_history_id=" ) + history_res );

    array<double> CL = GetDoubleResults( history_res, "CLtot", 0 );
    array<double> CD = GetDoubleResults( history_res, "CDtot", 0 );
    array<double> CMy = GetDoubleResults( history_res, "CMytot", 0 );

    if ( CL.length() == 0 ) { CL = GetDoubleResults( history_res, "CL", 0 ); }
    if ( CD.length() == 0 ) { CD = GetDoubleResults( history_res, "CD", 0 ); }
    if ( CMy.length() == 0 ) { CMy = GetDoubleResults( history_res, "CMy", 0 ); }

    double cl_v = 0.0;
    double cd_v = 0.0;
    double cm_v = 0.0;
    if ( CL.length() > 0 ) { cl_v = CL[ int(CL.length()) - 1 ]; }
    if ( CD.length() > 0 ) { cd_v = CD[ int(CD.length()) - 1 ]; }
    if ( CMy.length() > 0 ) { cm_v = CMy[ int(CMy.length()) - 1 ]; }

    Print( string( "yard_sea_CL=" ) + cl_v );
    Print( string( "yard_sea_CD=" ) + cd_v );
    Print( string( "yard_sea_CM=" ) + cm_v );
    Print( string( "yard_sea_vspaero_ok" ) );

    while ( GetNumTotalErrors() > 0 )
    {
        ErrorObj err = PopLastError();
        Print( err.GetErrorString() );
    }
}
"""


@dataclass
class VSPAEROAvailability:
    vspscript: str | None = None
    vspaero: str | None = None
    version: str | None = None
    # None = not probed (hand-built availability, e.g. tests); False = found
    # on disk but the loader could not start it (missing .so etc.).
    loads: bool | None = None
    load_error: str | None = None

    @property
    def available(self) -> bool:
        return bool(self.vspscript and self.vspaero) and self.loads is not False

    def to_dict(self) -> dict[str, Any]:
        return {
            "vspscript": self.vspscript,
            "vspaero": self.vspaero,
            "version": self.version,
            "loads": self.loads,
            "load_error": self.load_error,
            "available": self.available,
            "install_hint": (
                "Prefer vendor/openvsp from Ubuntu .deb extract "
                "(docs/OPENVSP_INSTALL.md). Need both vspscript and vspaero."
            ),
        }


def _find_exe(name: str) -> Path | None:
    vend = _VENDOR_OPENVSP / name
    if vend.is_file() and os.access(vend, os.X_OK):
        return vend
    which = shutil.which(name)
    return Path(which) if which else None


def detect() -> VSPAEROAvailability:
    """Probe vendor/PATH for vspscript + vspaero and check both binaries load."""
    vspscript = _find_exe("vspscript")
    vspaero = _find_exe("vspaero")
    version = "cli" if vspscript else None
    loads: bool | None = None
    load_error: str | None = None
    if vspscript and vspaero:
        # Existence is not availability: both binaries must actually load.
        errs = []
        for name, path in (("vspscript", vspscript), ("vspaero", vspaero)):
            pr = binprobe.probe(path)
            if not pr.ok:
                errs.append(f"{name}:{pr.reason}")
        loads = not errs
        load_error = "; ".join(errs) or None
    return VSPAEROAvailability(
        vspscript=str(vspscript) if vspscript else None,
        vspaero=str(vspaero) if vspaero else None,
        version=version,
        loads=loads,
        load_error=load_error,
    )


def parse_markers(text: str) -> dict[str, float | None]:
    """Parse ``yard_sea_CL/CD/CM=`` markers from vspscript stdout."""
    out: dict[str, float | None] = {"CL": None, "CD": None, "CM": None}
    for key, val in _MARKER_RE.findall(text):
        try:
            out[key] = float(val)
        except ValueError:
            continue
    return out


def parse_polar(path: Path) -> dict[str, float | None]:
    """Parse last data row of a VSPAERO ``*.polar`` for CLtot/CDtot/CMytot.

    Polar columns (header line starting with ``Beta``): Beta Mach AoA Re/1e6
    CLo CLi CLtot CDo CDi CDtot … CMxtot CMytot CMztot …
    """
    empty: dict[str, float | None] = {"CL": None, "CD": None, "CM": None}
    if not path.is_file():
        return empty
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    header_idx = None
    for i, line in enumerate(lines):
        toks = line.split()
        if toks and toks[0] == "Beta" and "CLtot" in toks and "CDtot" in toks:
            header_idx = i
            headers = toks
            break
    if header_idx is None:
        return empty
    try:
        i_cl = headers.index("CLtot")
        i_cd = headers.index("CDtot")
        i_cm = headers.index("CMytot")
    except ValueError:
        return empty
    data_row = None
    for line in lines[header_idx + 1 :]:
        toks = line.split()
        if len(toks) <= max(i_cl, i_cd, i_cm):
            continue
        try:
            float(toks[0])
        except ValueError:
            continue
        data_row = toks
    if data_row is None:
        return empty
    try:
        return {
            "CL": float(data_row[i_cl]),
            "CD": float(data_row[i_cd]),
            "CM": float(data_row[i_cm]),
        }
    except (ValueError, IndexError):
        return empty


def _env_with_vendor(vspscript: str) -> dict[str, str]:
    env = os.environ.copy()
    vend = str(Path(vspscript).resolve().parent)
    prev = env.get("PATH", "")
    if vend not in prev.split(os.pathsep):
        env["PATH"] = vend + os.pathsep + prev
    return env


def _run_vspaero_script(
    vspscript: str,
    work: Path,
    *,
    alpha_deg: float,
    timeout_sec: float = 120.0,
) -> dict[str, Any]:
    # Absolute paths: relative work_dir (e.g. out/foo) makes AngelScript
    # GetModule fail with "Error ExecuteScript GetModule".
    work = work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    script_path = work / "yard_sea_vspaero.vspscript"
    body = _VSPAERO_SCRIPT.replace("ALPHA_PLACEHOLDER", f"{float(alpha_deg):.6f}")
    script_path.write_text(body, encoding="utf-8")

    proc = subprocess.run(
        # Pass filename only; cwd is the work dir (avoids path-as-module issues).
        [vspscript, "-script", script_path.name],
        cwd=str(work),
        capture_output=True,
        text=True,
        timeout=timeout_sec,
        check=False,
        env=_env_with_vendor(vspscript),
    )
    combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
    markers = parse_markers(combined)
    polar = parse_polar(work / "yard_sea_vspaero.polar")

    cl = markers["CL"] if markers["CL"] is not None else polar["CL"]
    cd = markers["CD"] if markers["CD"] is not None else polar["CD"]
    cm = markers["CM"] if markers["CM"] is not None else polar["CM"]

    ok_marker = "yard_sea_vspaero_ok" in combined
    wrote_vsp3 = (work / "yard_sea_vspaero.vsp3").is_file()
    compile_err = "Error ExecuteScript" in combined or " : ERR  :" in combined
    have_coeffs = cl is not None and cd is not None and cm is not None

    return {
        "returncode": proc.returncode,
        "stdout": proc.stdout or "",
        "stderr": proc.stderr or "",
        "ok_marker": ok_marker,
        "wrote_vsp3": wrote_vsp3,
        "compile_err": compile_err,
        "CL": cl,
        "CD": cd,
        "CM": cm,
        "source": (
            "markers"
            if markers["CL"] is not None
            else ("polar" if polar["CL"] is not None else None)
        ),
        "success": bool(ok_marker and have_coeffs and not compile_err),
        "vsp3_bytes": (
            (work / "yard_sea_vspaero.vsp3").stat().st_size if wrote_vsp3 else 0
        ),
    }


def run(
    *,
    alpha_deg: float = 2.0,
    availability: VSPAEROAvailability | None = None,
    work_dir: str | None = None,
    model_path: str | None = None,
    timeout_sec: float = 120.0,
) -> dict[str, Any]:
    """Run thin-wing VSPAERO via vspscript; skip cleanly if unavailable.

    ``model_path`` is accepted for protocol compatibility but the current
    L1 vehicle always builds an in-script rectangular wing (ignore load).
    """
    avail = availability if availability is not None else detect()
    if not avail.available:
        return {
            "teacher": TEACHER,
            "skipped": True,
            "skip_reason": (
                "vspaero_binary_load_failed" if avail.loads is False else "vspaero_unavailable"
            ),
            "fidelity": FIDELITY_PENDING,
            "CL": None,
            "CD": None,
            "CM": None,
            "alpha_deg": alpha_deg,
            "model_path": model_path,
            "availability": avail.to_dict(),
            "notes": (
                "VSPAERO L1 teacher — vspscript/vspaero absent. "
                "Not cert / not operational."
            ),
        }

    assert avail.vspscript is not None
    try:
        if work_dir:
            work = Path(work_dir)
            work.mkdir(parents=True, exist_ok=True)
            detail = _run_vspaero_script(
                avail.vspscript, work, alpha_deg=alpha_deg, timeout_sec=timeout_sec
            )
        else:
            with tempfile.TemporaryDirectory(prefix="yard_vspaero_") as td:
                detail = _run_vspaero_script(
                    avail.vspscript,
                    Path(td),
                    alpha_deg=alpha_deg,
                    timeout_sec=timeout_sec,
                )
    except subprocess.TimeoutExpired:
        return {
            "teacher": TEACHER,
            "skipped": True,
            "skip_reason": "vspaero_timeout",
            "fidelity": FIDELITY_PENDING,
            "CL": None,
            "CD": None,
            "CM": None,
            "alpha_deg": alpha_deg,
            "model_path": model_path,
            "availability": avail.to_dict(),
            "notes": "VSPAERO vspscript timed out. Not cert / not operational.",
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
            "notes": f"VSPAERO run failed: {exc}. Not cert / not operational.",
        }

    if not detail["success"]:
        return {
            "teacher": TEACHER,
            "skipped": True,
            "skip_reason": "vspaero_script_failed",
            "fidelity": FIDELITY_PENDING,
            "CL": detail["CL"],
            "CD": detail["CD"],
            "CM": detail["CM"],
            "alpha_deg": alpha_deg,
            "model_path": model_path,
            "availability": avail.to_dict(),
            "cli": {
                "bin": avail.vspscript,
                "returncode": detail["returncode"],
                "ok_marker": detail["ok_marker"],
                "wrote_vsp3": detail["wrote_vsp3"],
                "compile_err": detail["compile_err"],
            },
            "notes": (
                "VSPAERO vspscript ran but CL/CD/CM not recovered. "
                "Not cert / not operational."
            ),
        }

    return {
        "teacher": TEACHER,
        "skipped": False,
        "skip_reason": None,
        "fidelity": FIDELITY,
        "CL": detail["CL"],
        "CD": detail["CD"],
        "CM": detail["CM"],
        "alpha_deg": alpha_deg,
        "model_path": model_path,
        "availability": avail.to_dict(),
        "cli": {
            "bin": avail.vspscript,
            "vspaero": avail.vspaero,
            "returncode": detail["returncode"],
            "vsp3_bytes": detail["vsp3_bytes"],
            "coeff_source": detail["source"],
        },
        "notes": (
            "VSPAERO L1 thin wing OK "
            "(VSPAEROComputeGeometry + VSPAEROSweep @ "
            f"alpha={alpha_deg} deg). Vortex-lattice exploratory only. "
            "Not cert / not operational."
        ),
    }


def run_teacher(**kwargs: Any) -> dict[str, Any]:
    return run(**kwargs)
