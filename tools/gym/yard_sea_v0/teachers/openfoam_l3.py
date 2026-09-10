"""L3 OpenFOAM resistance teacher interface for Yard-Sea-v0.

Fidelity labels:
- L3_pending — case prepared / FOAM absent / forceCoeffs missing (default here)
- L3_openfoam — parsed forceCoeffs from a real solver run (when FOAM available)

This module scaffolds prepare_case / run_teacher without requiring OpenFOAM
on the machine. When FOAM/docker/singularity are absent, run_teacher returns
a ResistanceResult-like dict with fidelity=L3_pending and skipped=True.
"""

from __future__ import annotations

import math
import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from ..hull import G, RHO_SW
from ..resistance_l1 import ResistanceResult

# Repo-root cases/ maps to tools/gym/cases/ in the yard monorepo layout.
_PKG_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CASE_TEMPLATE = _PKG_ROOT / "cases" / "openfoam_hull_v0"
FIDELITY_PENDING = "L3_pending"
FIDELITY_OPENFOAM = "L3_openfoam"


@dataclass
class OpenFOAMAvailability:
    foam_bin: str | None = None
    foam_version: str | None = None
    docker: bool = False
    singularity: bool = False
    apptainer: bool = False
    wm_project_dir: str | None = None

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
        }


def _discover_wm_project_dir() -> str | None:
    """Return OpenFOAM project dir if present (env or Debian package layout)."""
    env = os.environ.get("WM_PROJECT_DIR")
    if env and Path(env).is_dir():
        return env
    # Debian openfoam package (trixie/bookworm): etc under /usr/share/openfoam
    debian = Path("/usr/share/openfoam")
    if (debian / "etc" / "controlDict").is_file():
        return str(debian)
    for cand in sorted(Path("/opt").glob("openfoam*")) if Path("/opt").is_dir() else []:
        if (cand / "etc" / "bashrc").is_file() or (cand / "etc" / "controlDict").is_file():
            return str(cand)
    return None


def _foam_environ(base: dict[str, str] | None = None) -> dict[str, str]:
    """Env vars so Debian /usr/bin/*Foam binaries find etc/controlDict."""
    env = dict(base if base is not None else os.environ)
    wm = _discover_wm_project_dir()
    if wm:
        env.setdefault("WM_PROJECT_DIR", wm)
        etc = str(Path(wm) / "etc")
        env.setdefault("FOAM_ETC", etc)
        env.setdefault("FOAM_CONFIG_ETC", etc)
        env.setdefault("WM_PROJECT", "OpenFOAM")
    return env


def _docker_cli() -> list[str] | None:
    """Return a working docker argv prefix, or None if docker unusable.

    Tries bare docker, then `sg docker`, then passwordless sudo.
    """
    if shutil.which("docker") is None:
        return None
    # First: bare docker info
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
    # sg docker
    if shutil.which("sg"):
        try:
            r = subprocess.run(
                ["sg", "docker", "-c", "docker info"],
                capture_output=True,
                timeout=8,
                check=False,
            )
            if r.returncode == 0:
                return ["sg", "docker", "-c"]  # caller appends docker ... as one string
        except (subprocess.SubprocessError, OSError):
            pass
    # sudo -n docker
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
    # Binary exists but daemon not usable — still advertise docker for detect
    return ["docker"]


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
        # Debian package has no foamVersion; infer from package layout / dpkg.
        wm = _discover_wm_project_dir()
        if wm and Path(wm).name == "openfoam":
            version = "OPENFOAM=1912 (debian)"
        else:
            version = "openfoam-detected"
        # Prefer dpkg version when available (no side effects beyond dpkg-query)
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
    return OpenFOAMAvailability(
        foam_bin=foam_bin,
        foam_version=version,
        docker=docker_present,
        singularity=shutil.which("singularity") is not None,
        apptainer=shutil.which("apptainer") is not None,
        wm_project_dir=wm,
    )


def _estimate_l_from_stl(stl_path: Path) -> float:
    """Best-effort LOA from ASCII STL vertex x-extent; default 120 m."""
    xmin, xmax = None, None
    try:
        text = Path(stl_path).read_text(errors="ignore")
    except OSError:
        return 120.0
    for m in re.finditer(
        r"vertex\s+([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)", text
    ):
        x = float(m.group(1))
        xmin = x if xmin is None else min(xmin, x)
        xmax = x if xmax is None else max(xmax, x)
    if xmin is None or xmax is None or xmax <= xmin:
        return 120.0
    return float(xmax - xmin)


def _rewrite_placeholders(path: Path, mapping: dict[str, str]) -> None:
    text = path.read_text()
    for key, val in mapping.items():
        text = text.replace(key, val)
    path.write_text(text)


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
    """Copy case template, inject STL + freestream from Fn, return case dir.

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

    L_ref = float(L) if L is not None else _estimate_l_from_stl(stl_path)
    B_ref = float(B) if B is not None else max(L_ref / 6.0, 1.0)
    T_ref = float(T) if T is not None else max(L_ref / 15.0, 0.5)
    U = float(Fn) * math.sqrt(G * L_ref)
    A_ref = max(L_ref * T_ref * 0.1, 1.0)  # frontal-ish placeholder

    mapping = {
        "__UX__": f"{U:.6g}",
        "__MAG_U_INF__": f"{U:.6g}",
        "__L_REF__": f"{L_ref:.6g}",
        "__A_REF__": f"{A_ref:.6g}",
    }
    for rel in ("0/U", "system/controlDict"):
        p = out_dir / rel
        if p.is_file():
            _rewrite_placeholders(p, mapping)

    meta = out_dir / "yard_sea_prepare.json"
    import json

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
                "fidelity": FIDELITY_PENDING,
                "template": str(template_dir),
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )
    return out_dir


_FORCE_COEFF_LINE = re.compile(
    r"^\s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)"
    r"(?:\s+([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?))+"
)


def parse_force_coeffs(path: str | Path) -> dict[str, float] | None:
    """Parse OpenFOAM postProcessing forceCoeffs.dat; return last Cd/Cl/Cm row.

    Expected columns (OpenFOAM forceCoeffs):
    Time Cd Cl Cm ...  (header may vary; we take col1=Cd, col2=Cl when present)
    """
    path = Path(path)
    if not path.is_file():
        return None
    last: list[float] | None = None
    for line in path.read_text(errors="ignore").splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
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
    # Typical: Time Cd Cl CmPitch ...
    out: dict[str, float] = {"time": last[0]}
    if len(last) >= 2:
        out["Cd"] = last[1]
    if len(last) >= 3:
        out["Cl"] = last[2]
    if len(last) >= 4:
        out["Cm"] = last[3]
    return out


def find_force_coeffs(case_dir: Path) -> Path | None:
    """Locate newest forceCoeffs.dat under postProcessing/."""
    root = Path(case_dir) / "postProcessing"
    if not root.is_dir():
        return None
    candidates = sorted(root.rglob("forceCoeffs.dat"), key=lambda p: p.stat().st_mtime)
    return candidates[-1] if candidates else None


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
            "OpenFOAM L3 teacher scaffold; no forceCoeffs yet. "
            f"Skip reason: {reason}. Not ITTC powering."
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
) -> dict[str, Any]:
    Cd = float(coeffs.get("Cd", float("nan")))
    U = Fn * math.sqrt(G * L)
    # Map Cd ~ Ct exploratory; S unknown → leave Rt_N from Cd * dynamic pressure * Aref proxy
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
        fidelity=FIDELITY_OPENFOAM,
        notes=(
            "Parsed OpenFOAM forceCoeffs Cd as Ct proxy. "
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
        }
    )
    return base


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
        prepared = prepare_case(
            stl_path, Fn, out_dir, L=L, B=B, T=T
        )

    L_ref = float(L) if L is not None else _estimate_l_from_stl(
        prepared / "constant" / "triSurface" / "hull.stl"
    )

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

    # Prefer native foam binaries with Debian-compatible FOAM_ETC env.
    # Allrun requires WM_PROJECT_DIR/bin/tools (missing on Debian package), so
    # invoke blockMesh / checkMesh / potentialFoam directly.
    try:
        if avail.foam_bin:
            foam_env = _foam_environ()
            # Use cwd=case only (relative -case doubles path under OpenFOAM).
            case_cwd = str(prepared.resolve())
            cmds = [
                ["blockMesh"],
                ["checkMesh"],
                ["potentialFoam", "-writephi"],
            ]
            for cmd in cmds:
                # potentialFoam may lack -writephi on some builds — retry plain
                try:
                    r = subprocess.run(
                        cmd,
                        cwd=case_cwd,
                        check=False,
                        timeout=timeout_s,
                        capture_output=True,
                        text=True,
                        env=foam_env,
                    )
                except subprocess.TimeoutExpired:
                    raise
                if r.returncode != 0 and cmd[0] == "potentialFoam" and "-writephi" in cmd:
                    r = subprocess.run(
                        ["potentialFoam"],
                        cwd=case_cwd,
                        check=False,
                        timeout=timeout_s,
                        capture_output=True,
                        text=True,
                        env=foam_env,
                    )
                # Write logs for debugging smoke runs
                log = prepared / f"log.{cmd[0]}"
                try:
                    log.write_text(
                        (r.stdout or "") + (r.stderr or ""),
                        encoding="utf-8",
                        errors="ignore",
                    )
                except OSError:
                    pass
        elif avail.docker:
            img = os.environ.get(
                "YARD_SEA_OPENFOAM_IMAGE", "opencfd/openfoam-default:2412"
            )
            inner = (
                "source /openfoam/profile.rc 2>/dev/null || "
                "source /opt/openfoam*/etc/bashrc 2>/dev/null || true; "
                "cd /case; "
                "blockMesh -case /case && "
                "checkMesh -case /case && "
                "(potentialFoam -case /case -writephi || potentialFoam -case /case) "
                "|| true"
            )
            cli = _docker_cli() or ["docker"]
            if cli[:2] == ["sg", "docker"]:
                # sg docker -c 'docker run ...'
                docker_argv = (
                    f"docker run --rm -u $(id -u):$(id -g) "
                    f"-v {prepared.resolve()}:/case -w /case {img} "
                    f"bash -lc {inner!r}"
                )
                subprocess.run(
                    ["sg", "docker", "-c", docker_argv],
                    check=False,
                    timeout=timeout_s,
                    capture_output=True,
                    text=True,
                )
            else:
                subprocess.run(
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
        else:
            return _pending_result(
                Fn,
                reason="no_runnable_backend",
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

    coeffs_path = find_force_coeffs(prepared)
    if coeffs_path is None:
        return _pending_result(
            Fn,
            reason="forceCoeffs_missing_after_run",
            case_dir=prepared,
            extra={"availability": avail.to_dict()},
        )
    coeffs = parse_force_coeffs(coeffs_path)
    if not coeffs or "Cd" not in coeffs:
        return _pending_result(
            Fn,
            reason="forceCoeffs_unparsed",
            case_dir=prepared,
            extra={"availability": avail.to_dict(), "coeffs_path": str(coeffs_path)},
        )
    return _result_from_coeffs(Fn, coeffs, case_dir=prepared, L=L_ref)


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
