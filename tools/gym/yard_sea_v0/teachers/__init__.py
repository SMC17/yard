"""Optional external teachers (L1.5 Michell, L3 CFD, Strip aero oracles).

Teacher protocol (shared)
-------------------------
Every teacher module exposes:

* ``detect() -> Availability`` — side-effect-free probe (PATH / import / vendor).
  Availability objects have ``.available: bool`` and ``.to_dict()``.
* ``run(...) -> dict`` — evaluate or **skip cleanly**. Skips set
  ``skipped=True``, ``skip_reason=<str>``, and a ``*_pending`` fidelity label.
  Successful runs set ``skipped=False`` and a concrete fidelity string.
* ``run_teacher(...)`` — alias of ``run`` for gallery / CLI uniformity.

Result dict conventions (honesty):

* Always include ``teacher`` (module short name) and ``notes``.
* Never claim certification, ITTC powering, class society, FAA, or operational
  approval. Sea L1/L1.5/L3 and aero stubs are exploratory ranking / scaffolding.
* Prefer ResistanceResult-shaped fields (Fn, Cw, Ct, Rt_N, fidelity) for hull
  teachers; aero stubs use CL/CD/CM (or FDM scalars) instead.

Fidelity ladder (Yard-Sea ↔ Strip bridge):

* L0 — algebraic / hydrostatic reject
* L1 — Holtrop-simplified calm-water rank
* L1.5 — Michell thin-ship wave drag (``michell_l15``)
* L2 — Capytaine panel/BEM ranking proxies (``panel_l2``; L2_panel_bem / L2_pending)
* L3 — OpenFOAM calm-water teacher (``openfoam_l3``; L3_potential / L3_rans / L3_pending)
* aero_* — OpenVSP / VSPAERO L1 / NeuralFoil / JSBSim Strip-path oracles

See ``docs/STRIP_ORACLES.md`` and ``yard_sea_v0.strip_assurance``.
"""

from .openfoam_l3 import (
    FIDELITY_PENDING,
    FIDELITY_POTENTIAL,
    FIDELITY_RANS,
    OpenFOAMAvailability,
    detect_openfoam,
    parse_force_coeffs,
    prepare_case,
    run_teacher,
)
from . import michell_l15
from . import openvsp_stub
from . import neuralfoil_stub
from . import jsbsim_stub
from . import vspaero_l1
from . import panel_l2

__all__ = [
    "FIDELITY_PENDING",
    "FIDELITY_POTENTIAL",
    "FIDELITY_RANS",
    "OpenFOAMAvailability",
    "detect_openfoam",
    "parse_force_coeffs",
    "prepare_case",
    "run_teacher",
    "michell_l15",
    "openvsp_stub",
    "neuralfoil_stub",
    "jsbsim_stub",
    "vspaero_l1",
    "panel_l2",
]
