"""Optional external teachers (L3 CFD, etc.)."""

from .openfoam_l3 import (
    OpenFOAMAvailability,
    detect_openfoam,
    parse_force_coeffs,
    prepare_case,
    run_teacher,
)

__all__ = [
    "OpenFOAMAvailability",
    "detect_openfoam",
    "parse_force_coeffs",
    "prepare_case",
    "run_teacher",
]
