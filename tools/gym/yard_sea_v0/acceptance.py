"""Per-oracle acceptance gates: a number is only credited with a pass/fail verdict.

Search-under-evidence rule: every oracle result (L1 Holtrop-style, L1.5 Michell,
L2 panel, L3 OpenFOAM forceCoeffs) carries an ``acceptance`` block next to its
numbers. Downstream ranking / reward code credits the number only when
``acceptance["passed"]`` is True. A converged drag coefficient is NOT enough on
its own: for L3 we require every reported force coefficient (Cd, Cl, Cm) to be
settled over a trailing window.

These are *harness* checks (finite, inside the surrogate's stated envelope,
iteratively settled). They are not ITTC verification & validation, not grid
convergence studies, and not class-society acceptance.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

ACCEPTANCE_SCHEMA = "yard_sea_v0.acceptance.v1"

# Iterative-settling defaults for steady (pseudo-time) forceCoeffs histories.
DEFAULT_WINDOW_FRAC = 0.2  # trailing fraction of samples inspected
DEFAULT_MIN_SAMPLES = 20  # need at least this many rows to judge settling
DEFAULT_REL_TOL = 0.01  # (max-min)/|mean| over window
DEFAULT_ABS_TOL = 1e-4  # floor for near-zero coefficients (e.g. Cl of a symmetric hull)
DEFAULT_COEFFS: tuple[str, ...] = ("Cd", "Cl", "Cm")

# L1 envelope: mirrors HullState.clamp_soft Fn band and ITTC-57 line usage.
L1_FN_RANGE = (0.10, 0.35)
L1_RN_MIN = 1e5
L1_CT_RANGE = (1e-4, 0.05)


@dataclass
class Check:
    name: str
    passed: bool
    value: float | None = None
    threshold: float | None = None
    detail: str = ""
    # Advisory checks are recorded (evidence, failed advisories listed) but never
    # change the verdict: e.g. "outside the oracle's validated envelope".
    advisory: bool = False

    def to_dict(self) -> dict[str, Any]:
        d = {
            "name": self.name,
            "passed": bool(self.passed),
            "value": _json_float(self.value),
            "threshold": _json_float(self.threshold),
            "detail": self.detail,
        }
        if self.advisory:
            d["advisory"] = True
        return d


@dataclass
class AcceptanceResult:
    oracle: str
    checks: list[Check] = field(default_factory=list)
    notes: str = ""

    @property
    def passed(self) -> bool:
        gating = [c for c in self.checks if not c.advisory]
        return bool(gating) and all(c.passed for c in gating)

    @property
    def failed_checks(self) -> list[str]:
        return [c.name for c in self.checks if not c.passed and not c.advisory]

    @property
    def failed_advisories(self) -> list[str]:
        return [c.name for c in self.checks if not c.passed and c.advisory]

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema": ACCEPTANCE_SCHEMA,
            "oracle": self.oracle,
            "passed": self.passed,
            "failed_checks": self.failed_checks,
            "failed_advisories": self.failed_advisories,
            "checks": [c.to_dict() for c in self.checks],
            "notes": self.notes
            or "Harness acceptance only; not ITTC V&V, not class, not certification.",
        }


def _json_float(x: float | None) -> float | None:
    if x is None:
        return None
    try:
        xf = float(x)
    except (TypeError, ValueError):
        return None
    return xf if math.isfinite(xf) else None


def _finite(x: Any) -> bool:
    try:
        return x is not None and math.isfinite(float(x))
    except (TypeError, ValueError):
        return False


def is_accepted(result: Mapping[str, Any] | None) -> bool:
    """True only if a result dict carries an acceptance block that passed."""
    if not result:
        return False
    acc = result.get("acceptance")
    return isinstance(acc, Mapping) and acc.get("passed") is True


# --------------------------------------------------------------------------- L3
def parse_force_coeffs_history(path: str | Path) -> dict[str, list[float]] | None:
    """Parse every row of an OpenFOAM forceCoeffs.dat / coefficient.dat.

    Returns ``{"time": [...], "Cd": [...], "Cl": [...], "Cm": [...], ...}``.
    Header handling matches ``openfoam_l3.parse_force_coeffs`` (short and
    v1912+ expanded headers; ``CmPitch`` maps to ``Cm``).
    """
    path = Path(path)
    if not path.is_file():
        return None
    header: list[str] | None = None
    rows: list[list[float]] = []
    for line in path.read_text(errors="ignore").splitlines():
        s = line.strip()
        if not s:
            continue
        if s.startswith("#"):
            toks = s.lstrip("#").split()
            if toks and toks[0].lower() in ("time", "cd"):
                header = [t.lower() for t in toks]
            continue
        try:
            rows.append([float(x) for x in s.split()])
        except ValueError:
            continue
    if not rows:
        return None
    rename = {"time": "time", "cd": "Cd", "cl": "Cl", "cm": "Cm", "cmpitch": "Cm", "cs": "Cs"}
    cols = header if header else ["time", "cd", "cl", "cm"]
    out: dict[str, list[float]] = {}
    for i, name in enumerate(cols):
        key = rename.get(name)
        if key is None or key in out:
            continue
        vals = [r[i] for r in rows if i < len(r)]
        if len(vals) == len(rows):
            out[key] = vals
    return out if "Cd" in out else None


def settling_check(
    name: str,
    series: Sequence[float],
    *,
    window_frac: float = DEFAULT_WINDOW_FRAC,
    min_samples: int = DEFAULT_MIN_SAMPLES,
    rel_tol: float = DEFAULT_REL_TOL,
    abs_tol: float = DEFAULT_ABS_TOL,
) -> Check:
    """Trailing-window band check: (max-min) <= max(rel_tol*|mean|, abs_tol)."""
    n = len(series)
    if n < min_samples:
        return Check(
            f"{name}_settled", False, float(n), float(min_samples),
            f"only {n} samples (< {min_samples}); cannot judge settling",
        )
    if not all(_finite(v) for v in series):
        return Check(f"{name}_settled", False, None, None, "non-finite values in history")
    w = max(3, int(math.ceil(window_frac * n)))
    tail = [float(v) for v in series[-w:]]
    mean = sum(tail) / len(tail)
    band = max(tail) - min(tail)
    tol = max(rel_tol * abs(mean), abs_tol)
    return Check(
        f"{name}_settled", band <= tol, band, tol,
        f"trailing {w}/{n} samples: band={band:.3e}, mean={mean:.4e}",
    )


def accept_force_history(
    history: Mapping[str, Sequence[float]] | None,
    *,
    required: Iterable[str] = DEFAULT_COEFFS,
    **kw: Any,
) -> AcceptanceResult:
    """L3 acceptance: every required coefficient present, finite and settled."""
    res = AcceptanceResult(oracle="L3_openfoam_forceCoeffs")
    if not history:
        res.checks.append(Check("force_history_present", False, detail="no forceCoeffs history"))
        return res
    res.checks.append(Check("force_history_present", True))
    for coeff in required:
        series = history.get(coeff)
        if series is None:
            res.checks.append(Check(f"{coeff}_present", False, detail=f"{coeff} missing"))
            continue
        res.checks.append(settling_check(coeff, series, **kw))
    return res


def accept_force_coeffs_file(path: str | Path | None, **kw: Any) -> AcceptanceResult:
    hist = parse_force_coeffs_history(path) if path else None
    return accept_force_history(hist, **kw)


# --------------------------------------------------------------------------- L1
def accept_l1(resistance: Mapping[str, Any] | Any, *, hull: Any | None = None) -> AcceptanceResult:
    """L1 envelope acceptance (finite terms, Fn/Rn inside the formula's stated band).

    With ``hull`` given, two *advisory* checks are appended from
    ``yard_sea_v0.applicability``: inside the method's declared range, and inside
    the envelope where this oracle was validated against tank data. They are
    recorded but do not change ``passed``.
    """
    r = resistance.to_dict() if hasattr(resistance, "to_dict") else dict(resistance or {})
    res = AcceptanceResult(oracle=str(r.get("fidelity", "L1")))
    for k in ("Ct", "Cf", "Cw", "k1"):
        res.checks.append(Check(f"{k}_finite", _finite(r.get(k)), _json_float(r.get(k))))
    fn = r.get("Fn")
    lo, hi = L1_FN_RANGE
    res.checks.append(
        Check("Fn_in_envelope", _finite(fn) and lo <= float(fn) <= hi, _json_float(fn), hi,
              f"L1 band {lo}-{hi}")
    )
    rn = r.get("Rn")
    res.checks.append(Check("Rn_above_ittc57_floor", _finite(rn) and float(rn) >= L1_RN_MIN,
                            _json_float(rn), L1_RN_MIN))
    ct = r.get("Ct")
    clo, chi = L1_CT_RANGE
    res.checks.append(
        Check("Ct_plausible", _finite(ct) and clo <= float(ct) <= chi, _json_float(ct), chi,
              f"exploratory plausibility band {clo}-{chi}")
    )
    if _finite(r.get("Cw")):
        res.checks.append(Check("Cw_non_negative", float(r["Cw"]) >= 0.0, float(r["Cw"]), 0.0))
    if hull is not None:
        from .applicability import assess

        ap = assess(hull, r.get("fidelity"))
        if ap["in_declared_range"] is not None:
            res.checks.append(Check("in_declared_method_range", ap["in_declared_range"],
                                    detail="; ".join(ap["declared_violations"]), advisory=True))
        if ap["in_validated_envelope"] is not None:
            res.checks.append(Check("in_tank_validated_envelope", ap["in_validated_envelope"],
                                    detail="; ".join(ap["envelope_violations"]), advisory=True))
    return res


# ---------------------------------------------------------- generic teacher dict
def accept_teacher_result(result: Mapping[str, Any] | None, *, keys: Sequence[str]) -> AcceptanceResult:
    """Generic gate for L1.5 / L2 teacher dicts: not skipped and named keys finite."""
    r = dict(result or {})
    res = AcceptanceResult(oracle=str(r.get("teacher") or r.get("fidelity") or "teacher"))
    res.checks.append(
        Check("not_skipped", not r.get("skipped", False), detail=str(r.get("skip_reason") or ""))
    )
    for k in keys:
        res.checks.append(Check(f"{k}_finite", _finite(r.get(k)), _json_float(r.get(k))))
    return res
