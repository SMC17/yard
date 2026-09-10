"""L1.5 Michell thin-ship wave-drag teacher for Yard-Sea-v0.

Wraps vendored Ship-D ``ModifiedMichellCw.ModMichell`` (Douglas Read / Bagazinski)
with a synthetic Wigley-like half-breadth grid from ``HullState`` when no Ship-D
offset mesh is supplied.

Fidelity: **L1.5_michell** — thin-ship wave-drag ranking only.
NOT ITTC powering, NOT model-test validated, NOT class / FAA / operational.
"""

from __future__ import annotations

import math
import sys
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..hull import G, RHO_SW, HullState
from ..resistance_l1 import ResistanceResult

_VENDOR = Path(__file__).resolve().parents[2] / "vendor" / "shipd_upstream"
FIDELITY = "L1.5_michell"
TEACHER = "michell_l15"


@dataclass
class MichellAvailability:
    vendor_mod: bool = False
    path: str | None = None

    @property
    def available(self) -> bool:
        return self.vendor_mod

    def to_dict(self) -> dict[str, Any]:
        return {
            "vendor_mod": self.vendor_mod,
            "path": self.path,
            "available": self.available,
            "install_hint": (
                "Vendored at vendor/shipd_upstream/ModifiedMichellCw.py "
                "(Ship-D / Harvard Dataverse lineage). No extra install."
            ),
        }


def detect() -> MichellAvailability:
    """Probe vendored ModifiedMichellCw (always expected in-repo)."""
    mod = _VENDOR / "ModifiedMichellCw.py"
    return MichellAvailability(vendor_mod=mod.is_file(), path=str(mod) if mod.is_file() else None)


def detect_michell() -> MichellAvailability:
    """Alias matching OpenFOAM-style detect_* naming."""
    return detect()


def _ensure_vendor_on_path() -> None:
    root = str(_VENDOR)
    if root not in sys.path:
        sys.path.insert(0, root)


def _load_mod_michell():
    if not detect().available:
        raise ImportError(f"ModifiedMichellCw missing at {_VENDOR}")
    _ensure_vendor_on_path()
    from ModifiedMichellCw import ModMichell, Calc_Cf  # type: ignore

    return ModMichell, Calc_Cf


def wigley_offsets(
    h: HullState,
    *,
    nx: int = 41,
    nz: int = 11,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Synthetic thin-ship half-breadth grid (Wigley-like) from HullState.

    Y[i,j] = half-beam at station X[i], waterline Z[j] (Z <= 0).
    Nx must be odd for Filon integration in ModMichell.
    """
    if nx % 2 == 0:
        nx += 1
    L, B, T = float(h.L), float(h.B), float(h.T)
    # Soft Cb taper: reduce midship beam slightly for lower-Cb hulls
    beam_scale = 0.5 * B * (0.85 + 0.15 * float(h.Cb))
    X = np.linspace(0.0, L, nx)
    Z = np.linspace(0.0, -T, nz)
    Y = np.zeros((nx, nz), dtype=np.float64)
    for i, x in enumerate(X):
        xi = 2.0 * x / L - 1.0  # [-1, 1]
        hull_x = max(0.0, 1.0 - xi * xi)
        for j, z in enumerate(Z):
            zi = (-z) / T if T > 0 else 0.0
            hull_z = max(0.0, 1.0 - zi * zi)
            Y[i, j] = beam_scale * hull_x * hull_z
    return Y, X, Z


def run(
    h: HullState | None = None,
    *,
    Fn: float | None = None,
    nx: int = 41,
    nz: int = 11,
    n_theta: int = 30,
    rho: float = RHO_SW,
    Y: np.ndarray | None = None,
    X: np.ndarray | None = None,
    Z: np.ndarray | None = None,
    availability: MichellAvailability | None = None,
) -> dict[str, Any]:
    """Compute Michell thin-ship wave drag for a hull (or explicit offset grid).

    Returns ResistanceResult-like dict plus Cw / Rw / U / teacher metadata.
    """
    avail = availability if availability is not None else detect()
    hull = h or HullState()
    fn = float(Fn if Fn is not None else hull.Fn)
    L = float(hull.L)
    U = fn * math.sqrt(G * L)

    if not avail.available:
        base = ResistanceResult(
            Fn=fn,
            Rn=0.0,
            Cf=0.0,
            k1=0.0,
            Cw=float("nan"),
            Rt_N=float("nan"),
            Ct=float("nan"),
            fidelity="L1.5_pending",
            notes="Michell vendor module missing. Not ITTC powering.",
        ).to_dict()
        base.update(
            {
                "skipped": True,
                "skip_reason": "michell_vendor_missing",
                "teacher": TEACHER,
                "Rw_N": None,
                "U": U,
                "availability": avail.to_dict(),
            }
        )
        return base

    offset_source = "wigley_synthetic"
    if Y is None or X is None or Z is None:
        Y, X, Z = wigley_offsets(hull, nx=nx, nz=nz)
    else:
        offset_source = "provided"
        Y = np.asarray(Y, dtype=np.float64)
        X = np.asarray(X, dtype=np.float64)
        Z = np.asarray(Z, dtype=np.float64)

    ModMichell, Calc_Cf = _load_mod_michell()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        rw = ModMichell(Y, U, X, Z, float(rho), int(n_theta))

    if rw == -1 or not np.isfinite(rw):
        base = ResistanceResult(
            Fn=fn,
            Rn=U * L / 1.19e-6,
            Cf=float("nan"),
            k1=float("nan"),
            Cw=float("nan"),
            Rt_N=float("nan"),
            Ct=float("nan"),
            fidelity="L1.5_pending",
            notes="ModMichell failed (Nx must be odd / numerical). Not ITTC.",
        ).to_dict()
        base.update(
            {
                "skipped": True,
                "skip_reason": "michell_failed",
                "teacher": TEACHER,
                "Rw_N": None,
                "U": U,
                "availability": avail.to_dict(),
            }
        )
        return base

    rw = float(rw)
    # Ship-D convention: Rw = 0.5 * Cw * rho * LOA^2 * U^2
    denom = 0.5 * float(rho) * (L**2) * (U**2)
    cw = rw / denom if denom > 0 else float("nan")

    sa = hull.wetted_approx()
    cf = float(Calc_Cf(U=U, WL=L))
    rf = 0.5 * cf * float(rho) * sa * U**2
    rt = rw + rf
    ct = rt / denom if denom > 0 else float("nan")
    rn = U * L / 1.19e-6

    base = ResistanceResult(
        Fn=fn,
        Rn=rn,
        Cf=cf,
        k1=float("nan"),
        Cw=cw,
        Rt_N=rt,
        Ct=ct,
        fidelity=FIDELITY,
        notes=(
            "Michell thin-ship wave drag (vendored ModifiedMichellCw) + ITTC57 Cf. "
            "Synthetic Wigley offsets unless Y/X/Z supplied. "
            "Exploratory L1.5 — not ITTC powering / not class / not operational."
        ),
    ).to_dict()
    base.update(
        {
            "skipped": False,
            "skip_reason": None,
            "teacher": TEACHER,
            "Rw_N": rw,
            "Rf_N": rf,
            "U": U,
            "S_m2": sa,
            "nx": int(Y.shape[0]),
            "nz": int(Y.shape[1]),
            "n_theta": int(n_theta),
            "offset_source": offset_source,
            "availability": avail.to_dict(),
        }
    )
    return base


def run_michell(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Alias for gallery / CLI."""
    return run(*args, **kwargs)


def run_teacher(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Shared teacher protocol alias."""
    return run(*args, **kwargs)
