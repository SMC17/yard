"""NeuralFoil airfoil aero oracle (Strip air path).

``detect()`` / ``run()`` skip cleanly if ``neuralfoil`` is not installed.
When present, ``run()`` performs a thin NACA0012-style Kulfan evaluation.

Install: ``pip install neuralfoil`` (pulls aerosandbox).

Not certification, not operational — ML surrogate for early explore only.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np

FIDELITY_PENDING = "aero_neuralfoil_pending"
FIDELITY = "aero_neuralfoil"
TEACHER = "neuralfoil_stub"


@dataclass
class NeuralFoilAvailability:
    python_mod: bool = False
    version: str | None = None
    aerosandbox: bool = False

    @property
    def available(self) -> bool:
        return self.python_mod

    def to_dict(self) -> dict[str, Any]:
        return {
            "python_mod": self.python_mod,
            "version": self.version,
            "aerosandbox": self.aerosandbox,
            "available": self.available,
            "install_hint": "pip install neuralfoil  # pulls aerosandbox",
        }


def detect() -> NeuralFoilAvailability:
    """Probe import for neuralfoil (no network)."""
    try:
        import neuralfoil as nf  # type: ignore

        version = getattr(nf, "version", None) or getattr(nf, "__version__", None)
        if callable(version):
            try:
                version = version()
            except Exception:
                version = str(version)
        try:
            import aerosandbox  # noqa: F401

            asb_ok = True
        except Exception:
            asb_ok = False
        return NeuralFoilAvailability(
            python_mod=True, version=str(version) if version else None, aerosandbox=asb_ok
        )
    except Exception:
        return NeuralFoilAvailability()


def _default_kulfan() -> dict[str, Any]:
    """NACA0012-ish Kulfan parameters via AeroSandbox when available."""
    try:
        import aerosandbox as asb

        af = asb.KulfanAirfoil("naca0012")
        return dict(af.kulfan_parameters)
    except Exception:
        # Symmetric thin foil fallback (8 weights)
        n = 8
        upper = np.array([0.17, 0.15, 0.17, 0.13, 0.16, 0.13, 0.15, 0.14])
        return {
            "lower_weights": -upper,
            "upper_weights": upper,
            "leading_edge_weight": 0.0,
            "TE_thickness": 0.0025,
        }


def run(
    *,
    alpha_deg: float = 2.0,
    Re: float = 1.0e6,
    model_size: str = "small",
    airfoil: str = "naca0012",
    kulfan_parameters: dict[str, Any] | None = None,
    availability: NeuralFoilAvailability | None = None,
) -> dict[str, Any]:
    """Thin NeuralFoil call; skip if package absent."""
    avail = availability if availability is not None else detect()
    if not avail.available:
        return {
            "teacher": TEACHER,
            "skipped": True,
            "skip_reason": "neuralfoil_unavailable",
            "fidelity": FIDELITY_PENDING,
            "CL": None,
            "CD": None,
            "CM": None,
            "alpha_deg": alpha_deg,
            "Re": Re,
            "airfoil": airfoil,
            "availability": avail.to_dict(),
            "notes": "neuralfoil not installed. pip install neuralfoil. Not cert.",
        }

    import neuralfoil as nf  # type: ignore

    kp = kulfan_parameters if kulfan_parameters is not None else _default_kulfan()
    raw = nf.get_aero_from_kulfan_parameters(
        kp, alpha=float(alpha_deg), Re=float(Re), model_size=model_size
    )

    def _scalar(key: str) -> float | None:
        if key not in raw:
            return None
        return float(np.asarray(raw[key]).reshape(-1)[0])

    cl, cd, cm = _scalar("CL"), _scalar("CD"), _scalar("CM")
    conf = _scalar("analysis_confidence")
    return {
        "teacher": TEACHER,
        "skipped": False,
        "skip_reason": None,
        "fidelity": FIDELITY,
        "CL": cl,
        "CD": cd,
        "CM": cm,
        "analysis_confidence": conf,
        "alpha_deg": alpha_deg,
        "Re": Re,
        "airfoil": airfoil,
        "model_size": model_size,
        "availability": avail.to_dict(),
        "notes": (
            "NeuralFoil ML airfoil surrogate (Kulfan). Exploratory Strip aero "
            "oracle — not cert / not operational / not flight-test validated."
        ),
    }


def run_teacher(**kwargs: Any) -> dict[str, Any]:
    return run(**kwargs)
