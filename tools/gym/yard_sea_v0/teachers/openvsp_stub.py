"""OpenVSP geometry/aero oracle stub (Strip air path).

``detect()`` / ``run()`` skip cleanly when OpenVSP binaries / Python bindings
are absent. Not certification, not operational.

Install hints (host-dependent; not pip-light on most Linux boxes):
- Download OpenVSP from https://openvsp.org/ (binary release)
- Or build from https://github.com/OpenVSP/OpenVSP
- Optional Python: ``openvsp`` package ships with some binary distributions
  (``import openvsp`` / ``vsp`` CLI on PATH)
"""

from __future__ import annotations

import shutil
from dataclasses import dataclass
from typing import Any

FIDELITY_PENDING = "aero_openvsp_pending"
FIDELITY = "aero_openvsp"
TEACHER = "openvsp_stub"


@dataclass
class OpenVSPAvailability:
    vsp_bin: str | None = None
    python_mod: bool = False
    version: str | None = None

    @property
    def available(self) -> bool:
        return bool(self.vsp_bin) or self.python_mod

    def to_dict(self) -> dict[str, Any]:
        return {
            "vsp_bin": self.vsp_bin,
            "python_mod": self.python_mod,
            "version": self.version,
            "available": self.available,
            "install_hint": (
                "Install OpenVSP binary from https://openvsp.org/ or build "
                "OpenVSP/OpenVSP; ensure `vsp` on PATH or `import openvsp`. "
                "No lightweight apt/pip package on this box."
            ),
        }


def detect() -> OpenVSPAvailability:
    """Probe PATH / import for OpenVSP (no side effects)."""
    vsp_bin = shutil.which("vsp") or shutil.which("vspscript")
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
    return OpenVSPAvailability(vsp_bin=vsp_bin, python_mod=python_mod, version=version)


def run(
    *,
    model_path: str | None = None,
    alpha_deg: float = 2.0,
    availability: OpenVSPAvailability | None = None,
) -> dict[str, Any]:
    """Attempt OpenVSP analysis; skip if unavailable.

    Real VSPAERO coupling is deferred — this stub only probes and returns
    pending fidelity unless a future adapter is wired.
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
    # Bindings present but full VSPAERO case not scaffolded yet.
    return {
        "teacher": TEACHER,
        "skipped": True,
        "skip_reason": "openvsp_adapter_pending",
        "fidelity": FIDELITY_PENDING,
        "CL": None,
        "CD": None,
        "CM": None,
        "alpha_deg": alpha_deg,
        "model_path": model_path,
        "availability": avail.to_dict(),
        "notes": (
            "OpenVSP detected but Yard adapter not yet wired to VSPAERO. "
            "Not cert / not operational."
        ),
    }


def run_teacher(**kwargs: Any) -> dict[str, Any]:
    return run(**kwargs)
