"""L3 OpenFOAM resistance teacher for Yard-Sea-v0.

Fidelity labels:
- L3_pending   — FOAM absent / timeout / disk / snappy or forceCoeffs missing
- L3_potential — parsed forceCoeffs from potentialFoam (irrotational smoke)
- L3_rans      — parsed forceCoeffs from simpleFoam (laminar RANS smoke)
- L3_openfoam  — alias kept for older callers (mapped to L3_potential)

Backend preference (auto):
1. Native mesh + native simpleFoam when forceCoeffs health-check passes
   (plain, or Debian-1912 SHA1 preload under tools/foam_sha1_fix/)
2. Native mesh + Docker OpenFOAM-2412 simpleFoam when native forces broken
3. Full Docker pipeline if no native FOAM binaries

Debian OpenFOAM 1912 libforces hits OSHA1stream/sha1buf::overflow FATAL
(mislabelled historically as OpenSSL sha1); OPENSSL_CONF does not fix it.

When FOAM/docker/singularity are absent, run_teacher returns a
ResistanceResult-like dict with fidelity=L3_pending and skipped=True.
"""

from __future__ import annotations

import json
import math
import os
import re
import shutil
import struct
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from ..hull import G, RHO_SW
from ..resistance_l1 import ResistanceResult

# Repo-root cases/ maps to tools/gym/cases/ in the yard monorepo layout.
_PKG_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CASE_TEMPLATE = _PKG_ROOT / "cases" / "openfoam_hull_v0"
FIDELITY_PENDING = "L3_pending"
FIDELITY_POTENTIAL = "L3_potential"
FIDELITY_RANS = "L3_rans"
FIDELITY_OPENFOAM = "L3_openfoam"  # backward-compat alias
DISK_SKIP_GB = 1.0


@dataclass
class OpenFOAMAvailability:
    foam_bin: str | None = None
    foam_version: str | None = None
    docker: bool = False
    singularity: bool = False
    apptainer: bool = False
    wm_project_dir: str | None = None
    native_forces_ok: bool = False
    native_forces_method: str | None = None  # "plain" | "sha1_preload"
    native_forces_detail: str | None = None

    @property
    def available(self) -> bool:
        return bool(self.foam_bin) or self.docker or self.singularity or self.apptainer

    def to_dict(self) -> dict[str, Any]:
        return {
            "foam_bin": self.foam_bin,
            "foam_version": self.foam_version,
            "docker": self.docker,
            "singularity": self.singularity,
            "apptainer": self.apptainer,
            "wm_project_dir": self.wm_project_dir,
            "available": self.available,
            "native_forces_ok": self.native_forces_ok,
            "native_forces_method": self.native_forces_method,
            "native_forces_detail": self.native_forces_detail,
        }


def _discover_wm_project_dir() -> str | None:
    """Return OpenFOAM project dir if present (env or Debian package layout)."""
    env = os.environ.get("WM_PROJECT_DIR")
    if env and Path(env).is_dir():
        return env
    debian = Path("/usr/share/openfoam")
    if (debian / "etc" / "controlDict").is_file():
        return str(debian)
    for cand in sorted(Path("/opt").glob("openfoam*")) if Path("/opt").is_dir() else []:
        if (cand / "etc" / "bashrc").is_file() or (cand / "etc" / "controlDict").is_file():
            return str(cand)
    return None


def _sha1_preload_so() -> Path | None:
    """Path to libfoam_sha1_check_bypass.so if present (or YARD_SEA_FOAM_SHA1_PRELOAD)."""
    env = os.environ.get("YARD_SEA_FOAM_SHA1_PRELOAD", "").strip()
    if env:
        p = Path(env)
        if p.is_file():
            return p
    cand = _PKG_ROOT / "tools" / "foam_sha1_fix" / "libfoam_sha1_check_bypass.so"
    if cand.is_file():
        return cand
    return None


def _ensure_sha1_preload_built() -> Path | None:
    """Build the SHA1 check-bypass .so from tools/ source if missing and gcc exists."""
    existing = _sha1_preload_so()
    if existing is not None:
        return existing
    src_dir = _PKG_ROOT / "tools" / "foam_sha1_fix"
    src = src_dir / "foam_sha1_check_bypass.c"
    so = src_dir / "libfoam_sha1_check_bypass.so"
    gcc = shutil.which("gcc")
    if not src.is_file() or gcc is None:
        return None
    try:
        subprocess.run(
            [gcc, "-shared", "-fPIC", "-O2", "-o", str(so), str(src)],
            check=True,
            timeout=60,
            capture_output=True,
            text=True,
        )
    except (subprocess.SubprocessError, OSError):
        return None
    return so if so.is_file() else None


def _sha1buf_missing_overflow(lib: Path | None = None) -> bool | None:
    """True if libOpenFOAM sha1buf has xsputn but no overflow (Debian 1912 bug).

    None if nm/lib unavailable (unknown).
    """
    if lib is None:
        for cand in (Path("/usr/lib/libOpenFOAM.so"), Path("/lib/libOpenFOAM.so")):
            if cand.is_file():
                lib = cand
                break
    if lib is None or not lib.is_file():
        return None
    nm = shutil.which("nm")
    if nm is None:
        return None
    try:
        out = subprocess.check_output(
            [nm, "-D", str(lib)], text=True, stderr=subprocess.DEVNULL, timeout=15
        )
    except (subprocess.SubprocessError, OSError):
        return None
    has_xsputn = "sha1buf6xsputn" in out
    has_overflow = "sha1buf8overflow" in out
    if not has_xsputn:
        return False
    return not has_overflow


def native_forces_health(*, ensure_preload: bool = True) -> dict[str, Any]:
    """Static health check for native libforces / forceCoeffs.

    Returns keys: ok, method ("plain"|"sha1_preload"|None), detail, sha1_bug.
    """
    broken = _sha1buf_missing_overflow()
    preload = _ensure_sha1_preload_built() if ensure_preload else _sha1_preload_so()
    if broken is False:
        return {
            "ok": True,
            "method": "plain",
            "detail": "libOpenFOAM sha1buf appears intact (overflow present or no xsputn)",
            "sha1_bug": False,
            "preload": str(preload) if preload else None,
        }
    if broken is True:
        if preload is not None:
            return {
                "ok": True,
                "method": "sha1_preload",
                "detail": (
                    "Debian OpenFOAM 1912 OSHA1stream/sha1buf lacks overflow "
                    f"(gcc-12+ ABI); using LD_PRELOAD={preload}"
                ),
                "sha1_bug": True,
                "preload": str(preload),
            }
        return {
            "ok": False,
            "method": None,
            "detail": (
                "Debian OpenFOAM 1912 OSHA1stream/sha1buf lacks overflow "
                "(IOstream 'sha1' FATAL on libforces). OPENSSL_CONF/SECLEVEL "
                "does not help. Build tools/foam_sha1_fix or use Docker OF-2412."
            ),
            "sha1_bug": True,
            "preload": None,
        }
    # unknown — prefer Docker if available; allow plain attempt
    return {
        "ok": False,
        "method": None,
        "detail": "Could not nm-inspect libOpenFOAM; treating native forces as unverified",
        "sha1_bug": False,
        "preload": str(preload) if preload else None,
    }


def _foam_environ(
    base: dict[str, str] | None = None,
    *,
    sha1_preload: bool = False,
) -> dict[str, str]:
    """Env vars so Debian /usr/bin/*Foam binaries find etc/controlDict."""
    env = dict(base if base is not None else os.environ)
    wm = _discover_wm_project_dir()
    if wm:
        env.setdefault("WM_PROJECT_DIR", wm)
        etc = str(Path(wm) / "etc")
        env.setdefault("FOAM_ETC", etc)
        env.setdefault("FOAM_CONFIG_ETC", etc)
        env.setdefault("WM_PROJECT", "OpenFOAM")
    if sha1_preload:
        so = _ensure_sha1_preload_built()
        if so is not None:
            prev = env.get("LD_PRELOAD", "").strip()
            sp = str(so.resolve())
            if prev:
                parts = [p for p in prev.split(":") if p and p != sp]
                env["LD_PRELOAD"] = sp + ((":" + ":".join(parts)) if parts else "")
            else:
                env["LD_PRELOAD"] = sp
    return env


def _docker_cli() -> list[str] | None:
    """Return a working docker argv prefix, or None if docker unusable."""
    if shutil.which("docker") is None:
        return None
    try:
        r = subprocess.run(
            ["docker", "info"],
            capture_output=True,
            timeout=8,
            check=False,
        )
        if r.returncode == 0:
            return ["docker"]
    except (subprocess.SubprocessError, OSError):
        pass
    if shutil.which("sg"):
        try:
            r = subprocess.run(
                ["sg", "docker", "-c", "docker info"],
                capture_output=True,
                timeout=8,
                check=False,
            )
            if r.returncode == 0:
                return ["sg", "docker", "-c"]
        except (subprocess.SubprocessError, OSError):
            pass
    if shutil.which("sudo"):
        try:
            r = subprocess.run(
                ["sudo", "-n", "docker", "info"],
                capture_output=True,
                timeout=8,
                check=False,
            )
            if r.returncode == 0:
                return ["sudo", "-n", "docker"]
        except (subprocess.SubprocessError, OSError):
            pass
    return ["docker"]



def _docker_usable() -> bool:
    """True if a docker CLI prefix can run `docker info` successfully."""
    if shutil.which("docker") is None:
        return False
    probes = [
        ["docker", "info"],
        ["sg", "docker", "-c", "docker info"],
        ["sudo", "-n", "docker", "info"],
    ]
    for cmd in probes:
        if cmd[0] == "sg" and shutil.which("sg") is None:
            continue
        if cmd[0] == "sudo" and shutil.which("sudo") is None:
            continue
        try:
            r = subprocess.run(cmd, capture_output=True, timeout=8, check=False)
            if r.returncode == 0:
                return True
        except (subprocess.SubprocessError, OSError):
            continue
    return False


def detect_openfoam() -> OpenFOAMAvailability:
    """Probe PATH / env for OpenFOAM or container runtimes (no side effects)."""
    foam_bin = None
    for name in ("potentialFoam", "simpleFoam", "foamVersion", "checkMesh"):
        path = shutil.which(name)
        if path:
            foam_bin = path
            break
    version = None
    if shutil.which("foamVersion"):
        try:
            version = subprocess.check_output(
                ["foamVersion"], text=True, stderr=subprocess.STDOUT, timeout=5
            ).strip()
        except (subprocess.SubprocessError, OSError):
            version = None
    if version is None and foam_bin:
        wm = _discover_wm_project_dir()
        if wm and Path(wm).name == "openfoam":
            version = "OPENFOAM=1912 (debian)"
        else:
            version = "openfoam-detected"
        try:
            ver = subprocess.check_output(
                ["dpkg-query", "-W", "-f=${Version}", "openfoam"],
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=5,
            ).strip()
            if ver:
                version = f"debian-openfoam {ver}"
        except (subprocess.SubprocessError, OSError, FileNotFoundError):
            pass
    wm = _discover_wm_project_dir()
    docker_present = shutil.which("docker") is not None
    health = native_forces_health(ensure_preload=True) if foam_bin else {
        "ok": False,
        "method": None,
        "detail": "no native foam_bin",
        "sha1_bug": False,
        "preload": None,
    }
    return OpenFOAMAvailability(
        foam_bin=foam_bin,
        foam_version=version,
        docker=docker_present,
        singularity=shutil.which("singularity") is not None,
        apptainer=shutil.which("apptainer") is not None,
        wm_project_dir=wm,
        native_forces_ok=bool(health.get("ok")),
        native_forces_method=health.get("method"),
        native_forces_detail=health.get("detail"),
    )


def stl_bbox(stl_path: str | Path) -> tuple[float, float, float, float, float, float] | None:
    """Return (xmin, xmax, ymin, ymax, zmin, zmax) for ASCII or binary STL."""
    path = Path(stl_path)
    try:
        data = path.read_bytes()
    except OSError:
        return None
    if len(data) < 84:
        return None
    head = data[:200]
    ascii_like = head.lstrip().lower().startswith(b"solid") and b"facet" in data[:4096]
    xs: list[float] = []
    ys: list[float] = []
    zs: list[float] = []
    if ascii_like:
        text = data.decode("ascii", errors="ignore")
        for line in text.splitlines():
            parts = line.split()
            if len(parts) >= 4 and parts[0] == "vertex":
                try:
                    xs.append(float(parts[1]))
                    ys.append(float(parts[2]))
                    zs.append(float(parts[3]))
                except ValueError:
                    continue
    else:
        ntri = struct.unpack_from("<I", data, 80)[0]
        if ntri <= 0 or ntri > 5_000_000:
            return None
        off = 84
        for _ in range(ntri):
            if off + 50 > len(data):
                break
            tri = struct.unpack_from("<12f", data, off)
            xs.extend((tri[3], tri[6], tri[9]))
            ys.extend((tri[4], tri[7], tri[10]))
            zs.extend((tri[5], tri[8], tri[11]))
            off += 50
    if not xs:
        return None
    return (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs))


def _estimate_l_from_stl(stl_path: Path) -> float:
    """Best-effort LOA from STL vertex x-extent; default 120 m."""
    bb = stl_bbox(stl_path)
    if bb is None or bb[1] <= bb[0]:
        return 120.0
    return float(bb[1] - bb[0])


def _rewrite_placeholders(path: Path, mapping: dict[str, str]) -> None:
    text = path.read_text()
    for key, val in mapping.items():
        text = text.replace(key, val)
    path.write_text(text)


def _clamp(n: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, n))


def _domain_from_bbox(
    bbox: tuple[float, float, float, float, float, float],
    L_ref: float,
) -> dict[str, float | int | str]:
    """Padded blockMesh domain + coarse cell counts + locationInMesh."""
    xmin, xmax, ymin, ymax, zmin, zmax = bbox
    L = max(L_ref, xmax - xmin, 1.0)
    B = max(ymax - ymin, L / 8.0, 0.5)
    T = max(zmax - zmin, L / 20.0, 0.2)
    x0 = xmin - 0.8 * L
    x1 = xmax + 1.6 * L
    y0 = ymin - 2.0 * B
    y1 = ymax + 2.0 * B
    z0 = zmin - 1.5 * T
    z1 = zmax + 2.5 * T
    # ~16 cells along L → coarse smoke (snappy level 1 near hull)
    cell = L / 16.0
    nx = _clamp(int(round((x1 - x0) / cell)), 12, 36)
    ny = _clamp(int(round((y1 - y0) / cell)), 8, 18)
    nz = _clamp(int(round((z1 - z0) / cell)), 8, 16)
    # locationInMesh: inlet plenum, off cell faces, above deck, outside hull
    dx = (x1 - x0) / nx
    dy = (y1 - y0) / ny
    dz = (z1 - z0) / nz
    loc_x = xmin - 0.35 * L
    loc_x = min(max(loc_x, x0 + 0.37 * dx), xmin - 0.05 * L)
    loc_y = 0.5 * (ymin + ymax) + 0.17 * dy
    loc_z = zmax + 0.45 * (z1 - zmax) + 0.13 * dz
    loc_z = min(max(loc_z, zmax + 0.2 * dz), z1 - 0.3 * dz)
    loc = f"({loc_x:.6g} {loc_y:.6g} {loc_z:.6g})"
    return {
        "xmin": x0,
        "xmax": x1,
        "ymin": y0,
        "ymax": y1,
        "zmin": z0,
        "zmax": z1,
        "nx": nx,
        "ny": ny,
        "nz": nz,
        "location": loc,
        "n_hex": nx * ny * nz,
    }





def _write_force_coeffs1_dict(
    case_dir: Path,
    *,
    mag_u: str,
    l_ref: str,
    a_ref: str,
) -> None:
    """Write system/forceCoeffs1 for postProcess / Docker FO."""
    content = """/*--------------------------------*- C++ -*----------------------------------*/
/* Yard-Sea-v0 forceCoeffs1 (postProcess / Docker)                          */
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    object      forceCoeffs1;
}
// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * //

type            forceCoeffs;
libs            ("libforces.so");
writeControl    timeStep;
writeInterval   1;
log             true;
patches         (hull);
rho             rhoInf;
rhoInf          1025;
liftDir         (0 0 1);
dragDir         (1 0 0);
CofR            (0 0 0);
pitchAxis       (0 1 0);
magUInf         MAGU;
lRef            LREF;
Aref            AREF;

// ************************************************************************* //
""".replace("MAGU", mag_u).replace("LREF", l_ref).replace("AREF", a_ref)
    (case_dir / "system" / "forceCoeffs1").write_text(content)


def prepare_case(
    stl_path: str | Path,
    Fn: float,
    out_dir: str | Path,
    *,
    L: float | None = None,
    B: float | None = None,
    T: float | None = None,
    template_dir: str | Path | None = None,
) -> Path:
    """Copy case template, inject STL + domain + freestream, return case dir.

    Does not require OpenFOAM — only filesystem writes.
    """
    stl_path = Path(stl_path)
    out_dir = Path(out_dir)
    template_dir = Path(template_dir) if template_dir else DEFAULT_CASE_TEMPLATE
    if not template_dir.is_dir():
        raise FileNotFoundError(f"OpenFOAM case template missing: {template_dir}")
    if not stl_path.is_file():
        raise FileNotFoundError(f"STL not found: {stl_path}")

    if out_dir.exists():
        shutil.rmtree(out_dir)
    shutil.copytree(template_dir, out_dir)

    tri = out_dir / "constant" / "triSurface"
    tri.mkdir(parents=True, exist_ok=True)
    dest_stl = tri / "hull.stl"
    shutil.copy2(stl_path, dest_stl)

    bbox = stl_bbox(stl_path)
    L_ref = float(L) if L is not None else (
        float(bbox[1] - bbox[0]) if bbox else _estimate_l_from_stl(stl_path)
    )
    B_ref = float(B) if B is not None else (
        float(bbox[3] - bbox[2]) if bbox else max(L_ref / 6.0, 1.0)
    )
    T_ref = float(T) if T is not None else (
        float(bbox[5] - bbox[4]) if bbox else max(L_ref / 15.0, 0.5)
    )
    U = float(Fn) * math.sqrt(G * L_ref)
    A_ref = max(B_ref * T_ref, 1e-3)

    if bbox is None:
        half_l, half_b, t = L_ref / 2.0, B_ref / 2.0, T_ref
        bbox = (-half_l, half_l, -half_b, half_b, 0.0, t)
    domain = _domain_from_bbox(bbox, L_ref)

    mapping = {
        "__UX__": f"{U:.6g}",
        "__MAG_U_INF__": f"{U:.6g}",
        "__L_REF__": f"{L_ref:.6g}",
        "__A_REF__": f"{A_ref:.6g}",
        "__XMIN__": f"{domain['xmin']:.6g}",
        "__XMAX__": f"{domain['xmax']:.6g}",
        "__YMIN__": f"{domain['ymin']:.6g}",
        "__YMAX__": f"{domain['ymax']:.6g}",
        "__ZMIN__": f"{domain['zmin']:.6g}",
        "__ZMAX__": f"{domain['zmax']:.6g}",
        "__NX__": str(int(domain["nx"])),
        "__NY__": str(int(domain["ny"])),
        "__NZ__": str(int(domain["nz"])),
        "__LOCATION_IN_MESH__": str(domain["location"]),
    }
    for rel in (
        "0/U",
        "system/controlDict",
        "system/blockMeshDict",
        "system/snappyHexMeshDict",
    ):
        p = out_dir / rel
        if p.is_file():
            _rewrite_placeholders(p, mapping)

    _write_force_coeffs1_dict(
        out_dir,
        mag_u=mapping["__MAG_U_INF__"],
        l_ref=mapping["__L_REF__"],
        a_ref=mapping["__A_REF__"],
    )

    meta = out_dir / "yard_sea_prepare.json"
    meta.write_text(
        json.dumps(
            {
                "stl": str(stl_path),
                "Fn": Fn,
                "L_ref": L_ref,
                "B_ref": B_ref,
                "T_ref": T_ref,
                "U": U,
                "A_ref": A_ref,
                "bbox": list(bbox),
                "domain": {k: domain[k] for k in domain},
                "fidelity": FIDELITY_PENDING,
                "template": str(template_dir),
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )
    return out_dir


def parse_force_coeffs(path: str | Path) -> dict[str, float] | None:
    """Parse OpenFOAM postProcessing forceCoeffs.dat; return last Cd/Cl/Cm row.

    Handles both short headers (Time Cd Cl Cm) and v1912+ expanded headers
    (Time Cd Cd(f) Cd(r) Cl ... CmPitch ...).
    """
    path = Path(path)
    if not path.is_file():
        return None
    header_cols: list[str] | None = None
    last: list[float] | None = None
    for line in path.read_text(errors="ignore").splitlines():
        s = line.strip()
        if not s:
            continue
        if s.startswith("#"):
            body = s.lstrip("#").strip()
            toks = body.split()
            if toks and toks[0].lower() in ("time", "cd"):
                header_cols = [t.lower() for t in toks]
            continue
        parts = s.split()
        try:
            vals = [float(x) for x in parts]
        except ValueError:
            continue
        if len(vals) >= 2:
            last = vals
    if not last:
        return None
    out: dict[str, float] = {}
    if header_cols and len(header_cols) >= 2:
        for i, name in enumerate(header_cols):
            if i >= len(last):
                break
            if name in ("time", "cd", "cl", "cm", "cs", "cmpitch", "cmyaw", "cmroll"):
                key = {"cmpitch": "Cm", "cmyaw": "CmYaw", "cmroll": "CmRoll"}.get(
                    name, name[0].upper() + name[1:] if name != "time" else "time"
                )
                if name == "time":
                    key = "time"
                elif name == "cd":
                    key = "Cd"
                elif name == "cl":
                    key = "Cl"
                elif name == "cm":
                    key = "Cm"
                elif name == "cs":
                    key = "Cs"
                out[key] = last[i]
        if "Cd" not in out and len(last) >= 2:
            out.setdefault("time", last[0])
            out["Cd"] = last[1]
    else:
        out["time"] = last[0]
        out["Cd"] = last[1]
        if len(last) >= 3:
            out["Cl"] = last[2]
        if len(last) >= 4:
            out["Cm"] = last[3]
    if "Cd" not in out:
        return None
    out.setdefault("time", last[0])
    return out


def find_force_coeffs(case_dir: Path) -> Path | None:
    """Locate newest forceCoeffs.dat / coefficient.dat under postProcessing/."""
    root = Path(case_dir) / "postProcessing"
    if not root.is_dir():
        return None
    names = ("forceCoeffs.dat", "coefficient.dat")
    candidates: list[Path] = []
    for name in names:
        candidates.extend(root.rglob(name))
    if not candidates:
        return None
    candidates.sort(key=lambda p: p.stat().st_mtime)
    return candidates[-1]


def _has_hull_patch(case_dir: Path) -> bool:
    boundary = Path(case_dir) / "constant" / "polyMesh" / "boundary"
    if not boundary.is_file():
        return False
    text = boundary.read_text(errors="ignore")
    return bool(re.search(r"\bhull\b", text))


def _disk_free_gb(path: Path) -> float:
    try:
        st = os.statvfs(path)
        return (st.f_bavail * st.f_frsize) / 1e9
    except OSError:
        return float("inf")



def _skip_reason_hint(reason: str) -> str:
    """Extra operator-facing hint for common skip reasons."""
    r = (reason or "").lower()
    if "sha1" in r:
        return (
            "Root cause: Debian OF-1912 OSHA1stream/sha1buf missing overflow "
            "(gcc-12+), not OpenSSL SECLEVEL. Fix: tools/foam_sha1_fix "
            "LD_PRELOAD or Docker opencfd/openfoam-default:2412. "
        )
    if reason in ("no_runnable_backend", "openfoam_unavailable"):
        return (
            "Need native OpenFOAM (+ optional SHA1 preload) or a usable Docker "
            "daemon with OpenFOAM image. "
        )
    if reason == "forceCoeffs_missing_after_run":
        return (
            "Solver finished without coefficient.dat/forceCoeffs.dat — check "
            "log.simpleFoam / Docker logs and hull patch. "
        )
    return ""


def _pending_result(
    Fn: float,
    *,
    reason: str,
    case_dir: Path | None = None,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    L_guess = 120.0
    U = Fn * math.sqrt(G * L_guess)
    base = ResistanceResult(
        Fn=Fn,
        Rn=0.0,
        Cf=0.0,
        k1=0.0,
        Cw=0.0,
        Rt_N=float("nan"),
        Ct=float("nan"),
        fidelity=FIDELITY_PENDING,
        notes=(
            "OpenFOAM L3 teacher; no forceCoeffs yet. "
            f"Skip reason: {reason}. "
            + _skip_reason_hint(reason)
            + " Not ITTC powering."
        ),
    ).to_dict()
    base.update(
        {
            "skipped": True,
            "skip_reason": reason,
            "case_dir": str(case_dir) if case_dir else None,
            "U": U,
            "Cd": None,
            "Cl": None,
            "Cm": None,
            "teacher": "openfoam_l3",
            "solver": None,
        }
    )
    if extra:
        base.update(extra)
    return base


def _result_from_coeffs(
    Fn: float,
    coeffs: dict[str, float],
    *,
    case_dir: Path,
    L: float,
    fidelity: str,
    solver: str,
) -> dict[str, Any]:
    Cd = float(coeffs.get("Cd", float("nan")))
    U = Fn * math.sqrt(G * L)
    S = L * L * 0.1
    Rt = 0.5 * RHO_SW * U * U * S * Cd if math.isfinite(Cd) else float("nan")
    base = ResistanceResult(
        Fn=Fn,
        Rn=U * L / 1.19e-6 if L > 0 else 0.0,
        Cf=float("nan"),
        k1=float("nan"),
        Cw=float("nan"),
        Rt_N=Rt,
        Ct=Cd,
        fidelity=fidelity,
        notes=(
            f"Parsed OpenFOAM forceCoeffs Cd as Ct proxy via {solver}. "
            "Exploratory L3 — not ITTC powering / not class."
        ),
    ).to_dict()
    base.update(
        {
            "skipped": False,
            "skip_reason": None,
            "case_dir": str(case_dir),
            "U": U,
            "Cd": coeffs.get("Cd"),
            "Cl": coeffs.get("Cl"),
            "Cm": coeffs.get("Cm"),
            "teacher": "openfoam_l3",
            "force_coeffs": coeffs,
            "solver": solver,
        }
    )
    return base


def _write_log(case_dir: Path, name: str, stdout: str, stderr: str) -> None:
    try:
        (case_dir / f"log.{name}").write_text(
            (stdout or "") + (stderr or ""),
            encoding="utf-8",
            errors="ignore",
        )
    except OSError:
        pass


def _run_logged(
    cmd: list[str],
    *,
    cwd: str,
    env: dict[str, str],
    timeout_s: float,
    log_name: str,
) -> subprocess.CompletedProcess[str]:
    r = subprocess.run(
        cmd,
        cwd=cwd,
        check=False,
        timeout=timeout_s,
        capture_output=True,
        text=True,
        env=env,
    )
    _write_log(Path(cwd), log_name, r.stdout or "", r.stderr or "")
    return r



def _set_application(case_dir: Path, app: str) -> None:
    ctrl = case_dir / "system" / "controlDict"
    if not ctrl.is_file():
        return
    txt = ctrl.read_text()
    txt = re.sub(
        r"application\s+\w+\s*;",
        f"application     {app};",
        txt,
        count=1,
    )
    ctrl.write_text(txt)


def _mesh_native(
    prepared: Path,
    foam_env: dict[str, str],
    timeout_s: float,
) -> str | None:
    """blockMesh → snappyHexMesh → checkMesh. Return skip_reason or None."""
    case_cwd = str(prepared.resolve())
    deadline = time.monotonic() + timeout_s

    def remaining() -> float:
        return max(8.0, deadline - time.monotonic())

    r = _run_logged(
        ["blockMesh"],
        cwd=case_cwd,
        env=foam_env,
        timeout_s=remaining(),
        log_name="blockMesh",
    )
    if r.returncode != 0:
        return "blockMesh_failed"
    if time.monotonic() >= deadline:
        return "timeout"

    r = _run_logged(
        ["snappyHexMesh", "-overwrite"],
        cwd=case_cwd,
        env=foam_env,
        timeout_s=remaining(),
        log_name="snappyHexMesh",
    )
    if r.returncode != 0:
        return "snappy_failed"
    if not _has_hull_patch(prepared):
        return "snappy_no_hull_patch"
    if time.monotonic() >= deadline:
        return "timeout"

    _run_logged(
        ["checkMesh"],
        cwd=case_cwd,
        env=foam_env,
        timeout_s=remaining(),
        log_name="checkMesh",
    )
    # Optional potential init (no functionObjects — Debian 1912 libforces hits sha1 bug).
    try:
        _run_logged(
            ["potentialFoam", "-writep", "-writephi"],
            cwd=case_cwd,
            env=foam_env,
            timeout_s=min(60.0, remaining()),
            log_name="potentialFoam",
        )
    except subprocess.TimeoutExpired:
        return "timeout"
    return None


def _docker_simplefoam(prepared: Path, timeout_s: float) -> tuple[str | None, str | None]:
    """Run short laminar simpleFoam in Docker for forceCoeffs (OpenFOAM-2412)."""
    img = os.environ.get("YARD_SEA_OPENFOAM_IMAGE", "opencfd/openfoam-default:2412")
    _set_application(prepared, "simpleFoam")
    inner = (
        "source /openfoam/profile.rc 2>/dev/null || true; "
        "cd /case; "
        "simpleFoam -case /case; "
        "echo SF_EXIT:$?"
    )
    cli = _docker_cli() or ["docker"]
    try:
        if cli[:2] == ["sg", "docker"]:
            docker_argv = (
                f"docker run --rm -u $(id -u):$(id -g) "
                f"-v {prepared.resolve()}:/case -w /case {img} "
                f"bash -lc {inner!r}"
            )
            r = subprocess.run(
                ["sg", "docker", "-c", docker_argv],
                check=False,
                timeout=timeout_s,
                capture_output=True,
                text=True,
            )
        else:
            r = subprocess.run(
                [
                    *cli,
                    "run",
                    "--rm",
                    "-u",
                    f"{os.getuid()}:{os.getgid()}",
                    "-v",
                    f"{prepared.resolve()}:/case",
                    "-w",
                    "/case",
                    img,
                    "bash",
                    "-lc",
                    inner,
                ],
                check=False,
                timeout=timeout_s,
                capture_output=True,
                text=True,
            )
        _write_log(prepared, "simpleFoam", r.stdout or "", r.stderr or "")
    except subprocess.TimeoutExpired:
        return None, "timeout"
    if find_force_coeffs(prepared) is not None:
        return "simpleFoam", None
    return None, "forceCoeffs_missing_after_run"


def _docker_full_pipeline(prepared: Path, timeout_s: float) -> tuple[str | None, str | None]:
    """Mesh + simpleFoam entirely inside Docker."""
    img = os.environ.get("YARD_SEA_OPENFOAM_IMAGE", "opencfd/openfoam-default:2412")
    _set_application(prepared, "simpleFoam")
    inner = (
        "source /openfoam/profile.rc 2>/dev/null || true; "
        "cd /case; "
        "blockMesh -case /case && "
        "snappyHexMesh -overwrite -case /case && "
        "checkMesh -case /case; "
        "simpleFoam -case /case || true; "
        "find /case/postProcessing -name coefficient.dat -o -name forceCoeffs.dat "
        "  2>/dev/null | head"
    )
    cli = _docker_cli() or ["docker"]
    try:
        if cli[:2] == ["sg", "docker"]:
            docker_argv = (
                f"docker run --rm -u $(id -u):$(id -g) "
                f"-v {prepared.resolve()}:/case -w /case {img} "
                f"bash -lc {inner!r}"
            )
            r = subprocess.run(
                ["sg", "docker", "-c", docker_argv],
                check=False,
                timeout=timeout_s,
                capture_output=True,
                text=True,
            )
        else:
            r = subprocess.run(
                [
                    *cli,
                    "run",
                    "--rm",
                    "-u",
                    f"{os.getuid()}:{os.getgid()}",
                    "-v",
                    f"{prepared.resolve()}:/case",
                    "-w",
                    "/case",
                    img,
                    "bash",
                    "-lc",
                    inner,
                ],
                check=False,
                timeout=timeout_s,
                capture_output=True,
                text=True,
            )
        _write_log(prepared, "docker_full", r.stdout or "", r.stderr or "")
    except subprocess.TimeoutExpired:
        return None, "timeout"
    if find_force_coeffs(prepared) is not None:
        return "simpleFoam", None
    if not _has_hull_patch(prepared):
        return None, "snappy_no_hull_patch"
    return None, "forceCoeffs_missing_after_run"


def _native_simplefoam(
    prepared: Path,
    foam_env: dict[str, str],
    timeout_s: float,
    *,
    sha1_preload: bool = False,
) -> tuple[str | None, str | None]:
    """Native simpleFoam (+ optional SHA1 LD_PRELOAD for Debian 1912)."""
    _set_application(prepared, "simpleFoam")
    env = _foam_environ(foam_env, sha1_preload=sha1_preload) if sha1_preload else foam_env
    try:
        r = _run_logged(
            ["simpleFoam"],
            cwd=str(prepared.resolve()),
            env=env,
            timeout_s=timeout_s,
            log_name="simpleFoam",
        )
    except subprocess.TimeoutExpired:
        return None, "timeout"
    if find_force_coeffs(prepared) is not None:
        return "simpleFoam", None
    log = (prepared / "log.simpleFoam").read_text(errors="ignore")
    if "sha1" in log.lower() or "osha1" in log.lower():
        return None, "forceCoeffs_sha1_bug"
    if r.returncode != 0:
        return None, "simpleFoam_failed"
    return None, "forceCoeffs_missing_after_run"



def run_teacher(
    stl_path: str | Path | None = None,
    Fn: float = 0.20,
    out_dir: str | Path | None = None,
    *,
    case_dir: str | Path | None = None,
    L: float | None = None,
    B: float | None = None,
    T: float | None = None,
    run: bool = True,
    timeout_s: float = 600.0,
    availability: OpenFOAMAvailability | None = None,
    solver: str = "auto",
) -> dict[str, Any]:
    """Prepare (optional) and attempt OpenFOAM L3 teacher.

    Returns ResistanceResult-like dict. If OpenFOAM is unavailable or run
    fails / yields no forceCoeffs, fidelity is L3_pending and skipped=True.
    """
    avail = availability if availability is not None else detect_openfoam()

    prepared: Path | None = Path(case_dir) if case_dir else None
    if prepared is None:
        if stl_path is None or out_dir is None:
            return _pending_result(
                Fn,
                reason="missing_stl_or_out_dir",
                extra={"availability": avail.to_dict()},
            )
        prepared = prepare_case(stl_path, Fn, out_dir, L=L, B=B, T=T)

    L_ref = float(L) if L is not None else _estimate_l_from_stl(
        prepared / "constant" / "triSurface" / "hull.stl"
    )

    skip_env = os.environ.get("YARD_SEA_L3_SKIP_SOLVE", "").strip().lower()
    if skip_env in ("1", "true", "yes"):
        run = False
    env_timeout = os.environ.get("YARD_SEA_L3_TIMEOUT", "").strip()
    if env_timeout:
        try:
            timeout_s = float(env_timeout)
        except ValueError:
            pass

    if not run:
        return _pending_result(
            Fn,
            reason="run_disabled",
            case_dir=prepared,
            extra={"availability": avail.to_dict()},
        )

    if not avail.available:
        return _pending_result(
            Fn,
            reason="openfoam_unavailable",
            case_dir=prepared,
            extra={"availability": avail.to_dict()},
        )

    free_gb = _disk_free_gb(prepared)
    if free_gb < DISK_SKIP_GB:
        return _pending_result(
            Fn,
            reason="disk_low",
            case_dir=prepared,
            extra={"availability": avail.to_dict(), "disk_free_gb": free_gb},
        )

    solver_used: str | None = None
    skip_reason: str | None = None
    backend_note: str | None = None
    health: dict[str, Any] = {}
    try:
        foam_env = _foam_environ()
        docker_ok = bool(avail.docker) and _docker_usable()
        health = native_forces_health(ensure_preload=True)
        # Refresh availability fields from live health (detect may be stale).
        avail.native_forces_ok = bool(health.get("ok"))
        avail.native_forces_method = health.get("method")
        avail.native_forces_detail = health.get("detail")
        use_preload = health.get("method") == "sha1_preload"
        solve_timeout = max(30.0, timeout_s * 0.5)

        # Prefer native forces when healthy; else Docker for forceCoeffs.
        if avail.foam_bin:
            mesh_reason = _mesh_native(prepared, foam_env, timeout_s)
            if mesh_reason:
                skip_reason = mesh_reason
            elif health.get("ok"):
                solver_used, skip_reason = _native_simplefoam(
                    prepared,
                    foam_env,
                    solve_timeout,
                    sha1_preload=use_preload,
                )
                backend_note = (
                    f"native_simpleFoam({health.get('method')})"
                    if solver_used
                    else None
                )
                if skip_reason and docker_ok:
                    solver_used, skip_reason = _docker_simplefoam(
                        prepared, solve_timeout
                    )
                    if solver_used:
                        backend_note = (
                            f"docker_fallback_after_native:{health.get('method')}"
                        )
            elif docker_ok:
                solver_used, skip_reason = _docker_simplefoam(prepared, solve_timeout)
                backend_note = "docker_simpleFoam_native_forces_unhealthy"
            else:
                # Last resort: attempt native (may sha1-FATAL) for a clear log.
                solver_used, skip_reason = _native_simplefoam(
                    prepared,
                    foam_env,
                    solve_timeout,
                    sha1_preload=bool(health.get("preload")),
                )
                if skip_reason == "forceCoeffs_sha1_bug":
                    skip_reason = "forceCoeffs_sha1_bug"
                    backend_note = health.get("detail")
        elif docker_ok:
            solver_used, skip_reason = _docker_full_pipeline(prepared, timeout_s)
            backend_note = "docker_full_pipeline"
        else:
            return _pending_result(
                Fn,
                reason="no_runnable_backend",
                case_dir=prepared,
                extra={
                    "availability": avail.to_dict(),
                    "native_forces_health": health,
                },
            )
    except subprocess.TimeoutExpired:
        return _pending_result(
            Fn,
            reason="timeout",
            case_dir=prepared,
            extra={"availability": avail.to_dict()},
        )
    except (subprocess.SubprocessError, OSError) as exc:
        return _pending_result(
            Fn,
            reason=f"run_error:{type(exc).__name__}",
            case_dir=prepared,
            extra={"availability": avail.to_dict(), "error": str(exc)},
        )

    if skip_reason and skip_reason not in ("simpleFoam_failed",):
        # Mesh/timeout failures: do not claim empty-box forceCoeffs.
        extra: dict[str, Any] = {
            "availability": avail.to_dict(),
            "solver": solver_used,
            "backend_note": backend_note,
            "native_forces_health": health or None,
        }
        coeffs_path = find_force_coeffs(prepared)
        if coeffs_path is None:
            return _pending_result(
                Fn, reason=skip_reason, case_dir=prepared, extra=extra
            )

    coeffs_path = find_force_coeffs(prepared)
    if coeffs_path is None:
        return _pending_result(
            Fn,
            reason=skip_reason or "forceCoeffs_missing_after_run",
            case_dir=prepared,
            extra={"availability": avail.to_dict(), "solver": solver_used},
        )
    coeffs = parse_force_coeffs(coeffs_path)
    if not coeffs or "Cd" not in coeffs:
        return _pending_result(
            Fn,
            reason="forceCoeffs_unparsed",
            case_dir=prepared,
            extra={
                "availability": avail.to_dict(),
                "coeffs_path": str(coeffs_path),
                "solver": solver_used,
            },
        )
    if solver_used == "simpleFoam":
        fidelity = FIDELITY_RANS
    else:
        fidelity = FIDELITY_POTENTIAL
    out = _result_from_coeffs(
        Fn,
        coeffs,
        case_dir=prepared,
        L=L_ref,
        fidelity=fidelity,
        solver=solver_used or "potentialFoam",
    )
    if backend_note:
        out["backend_note"] = backend_note
    out["native_forces_health"] = health or None
    # Acceptance gate: Cd/Cl/Cm must all be settled; the Cd number alone is not credited.
    from ..acceptance import accept_force_coeffs_file

    out["coeffs_path"] = str(coeffs_path)
    out["acceptance"] = accept_force_coeffs_file(coeffs_path).to_dict()
    return out


def maybe_annotate_gallery_child(
    child_stl: Path,
    Fn: float,
    l3_root: Path,
    *,
    enabled: bool,
) -> dict[str, Any] | None:
    """CLI helper: if enabled, run teacher (no-op pending without FOAM)."""
    if not enabled:
        return None
    out = l3_root / child_stl.stem
    return run_teacher(child_stl, Fn, out)
