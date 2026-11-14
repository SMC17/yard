"""JSBSim flight-dynamics oracle stub (Strip air path).

``detect()`` / ``run()`` skip cleanly if ``jsbsim`` is absent.
When present, ``run()`` loads a bundled model (default ``c172x``) and steps
a few integration cycles as a smoke / thin call.

Install: ``pip install jsbsim``

Not certification, not operational — FDM sandbox only.
"""

from __future__ import annotations

import contextlib
import io
import tempfile
from dataclasses import dataclass
from typing import Any

FIDELITY_PENDING = "aero_jsbsim_pending"
FIDELITY = "aero_jsbsim"
TEACHER = "jsbsim_stub"


@dataclass
class JSBSimAvailability:
    python_mod: bool = False
    version: str | None = None
    root_dir: str | None = None

    @property
    def available(self) -> bool:
        return self.python_mod

    def to_dict(self) -> dict[str, Any]:
        return {
            "python_mod": self.python_mod,
            "version": self.version,
            "root_dir": self.root_dir,
            "available": self.available,
            "install_hint": "pip install jsbsim",
        }


def detect() -> JSBSimAvailability:
    """Probe import for jsbsim (no network)."""
    try:
        import jsbsim

        version = getattr(jsbsim, "__version__", None)
        root = None
        try:
            root = jsbsim.get_default_root_dir()
        except Exception:
            root = None
        return JSBSimAvailability(
            python_mod=True, version=str(version) if version else None, root_dir=root
        )
    except Exception:
        return JSBSimAvailability()


def run(
    *,
    model: str = "c172x",
    h_sl_ft: float = 1000.0,
    vc_kts: float = 100.0,
    n_steps: int = 10,
    availability: JSBSimAvailability | None = None,
) -> dict[str, Any]:
    """Thin JSBSim integrate; skip if package absent."""
    avail = availability if availability is not None else detect()
    if not avail.available:
        return {
            "teacher": TEACHER,
            "skipped": True,
            "skip_reason": "jsbsim_unavailable",
            "fidelity": FIDELITY_PENDING,
            "model": model,
            "sim_time_sec": None,
            "vt_fps": None,
            "qbar_psf": None,
            "alpha_rad": None,
            "availability": avail.to_dict(),
            "notes": "jsbsim not installed. pip install jsbsim. Not cert.",
        }

    import jsbsim

    # FGFDMExec is chatty on stdout — silence for teacher hygiene
    buf = io.StringIO()
    try:
        # Stock aircraft models carry <output> directives (e.g. c172x writes
        # JSBout172B.csv); keep that out of the caller's cwd / the repo tree.
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf), \
                tempfile.TemporaryDirectory(prefix="yard_jsbsim_") as out_dir:
            fdm = jsbsim.FGFDMExec(None)
            fdm.set_output_path(out_dir)
            ok = fdm.load_model(model)
            fdm.disable_output()
            if not ok:
                return {
                    "teacher": TEACHER,
                    "skipped": True,
                    "skip_reason": f"model_load_failed:{model}",
                    "fidelity": FIDELITY_PENDING,
                    "model": model,
                    "availability": avail.to_dict(),
                    "notes": f"JSBSim could not load model {model}. Not cert.",
                }
            fdm["ic/h-sl-ft"] = float(h_sl_ft)
            fdm["ic/vc-kts"] = float(vc_kts)
            fdm["ic/gamma-deg"] = 0.0
            fdm.run_ic()
            for _ in range(int(n_steps)):
                fdm.run()
            sim_time = float(fdm["simulation/sim-time-sec"])
            vt = float(fdm["velocities/vt-fps"])
            qbar = float(fdm["aero/qbar-psf"])
            alpha = float(fdm["aero/alpha-rad"])
    except Exception as exc:
        return {
            "teacher": TEACHER,
            "skipped": True,
            "skip_reason": f"run_error:{type(exc).__name__}",
            "fidelity": FIDELITY_PENDING,
            "model": model,
            "error": str(exc),
            "availability": avail.to_dict(),
            "notes": "JSBSim thin call failed. Not cert / not operational.",
        }

    return {
        "teacher": TEACHER,
        "skipped": False,
        "skip_reason": None,
        "fidelity": FIDELITY,
        "model": model,
        "sim_time_sec": sim_time,
        "vt_fps": vt,
        "qbar_psf": qbar,
        "alpha_rad": alpha,
        "h_sl_ft": h_sl_ft,
        "vc_kts": vc_kts,
        "n_steps": n_steps,
        "availability": avail.to_dict(),
        "notes": (
            "JSBSim FDM thin integrate (bundled aircraft). Strip aero oracle "
            "sandbox — not cert / not operational / not flight clearance."
        ),
    }


def run_teacher(**kwargs: Any) -> dict[str, Any]:
    return run(**kwargs)
