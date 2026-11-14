"""L1 calm-water resistance surrogate (Holtrop-Mennen inspired, exploratory).

Fidelity: L1 — Zig HM1984 (hm1984_zig) when binary present; else Python simplified_py.
NOT ITTC powering, NOT model-test validated, NOT class-society grade.
Formulas loosely follow Holtrop & Mennen 1982/1984 structure with simplifications
where full appendage/bulb terms do not apply to this parametric state.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

from .hull import G, RHO_SW, HullState


@dataclass
class ResistanceResult:
    Fn: float
    Rn: float
    Cf: float
    k1: float
    Cw: float
    Rt_N: float
    Ct: float
    fidelity: str = "simplified_py"
    notes: str = (
        "Exploratory HM-style estimate for ranking only; not ITTC powering claim."
    )

    def to_dict(self) -> dict[str, Any]:
        return {
            "Fn": self.Fn,
            "Rn": self.Rn,
            "Cf": self.Cf,
            "k1": self.k1,
            "Cw": self.Cw,
            "Rt_N": self.Rt_N,
            "Ct": self.Ct,
            "fidelity": self.fidelity,
            "notes": self.notes,
        }


def ittc57_cf(rn: float) -> float:
    if rn <= 1e5:
        rn = 1e5
    return 0.075 / (math.log10(rn) - 2.0) ** 2


def estimate_resistance(
    h: HullState,
    nu: float = 1.19e-6,
    *,
    prefer_zig_hm1984: bool = True,
) -> ResistanceResult:
    """Return calm-water total resistance estimate at h.Fn.

    Default: prefer Zig HM1984 when yard_sea_zig is present and works
    (fidelity ``hm1984_zig``). Falls back to Python Holtrop-simplified
    (``simplified_py``) if the binary is missing or HM1984 fails.
    Set prefer_zig_hm1984=False to force the Python path (parity tests).
    """
    if prefer_zig_hm1984:
        try:
            from .zig_bridge import estimate_resistance_zig, zig_available

            if zig_available():
                return estimate_resistance_zig(h, fidelity="hm1984")
        except Exception:
            pass
    L, B, T, Cb = h.L, h.B, h.T, h.Cb
    Fn = h.Fn
    U = Fn * math.sqrt(G * L)
    S = h.wetted_approx()
    Rn = U * L / nu
    Cf = ittc57_cf(Rn)

    # Holtrop-like form factor (1+k1) — simplified using L/B, Cb, T/B
    # HM uses c12, c13, etc.; we use a smooth surrogate for exploratory hulls.
    lr = L * (1.0 - Cb + 0.06 * Cb * (h.lcb_frac * 4.0 + 1.0) / (4.0 * Cb - 1.0 + 1e-6))
    lr = max(0.6 * L, min(L, lr))
    c14 = 1.0 + 0.011 * 10.0  # Cstern~10 aft-body soft default
    k1 = 0.93 + 0.487118 * c14 * (B / L) ** 1.06806 * (T / L) ** 0.46106 * (
        L / lr
    ) ** 0.121563 * (L**3 / max(h.volume(), 1.0)) ** 0.364569 * (1.0 - Cb) ** -0.604247
    k1 = max(0.1, min(0.8, k1 - 1.0))  # store as k, use (1+k)

    # Wave resistance coefficient — HM low-Fn branch simplified
    # c1 depends on T/B, B/L; use bounded exponential in Fn
    c7 = B / L
    if c7 < 0.11:
        c1 = 0.229577 * (c7**0.33333)
    elif c7 > 0.25:
        c1 = 0.5 - 0.0625 / c7
    else:
        c1 = 2223105.0 * (c7**3.78613) * ((T / B) ** 1.07961) * (90.0 - 70.0 * Cb) ** -1.37565
        c1 = max(0.5, min(50.0, c1 / 1e4))  # tame for exploratory

    d = -0.9
    m1 = (
        0.0140407 * (L / T)
        - 1.75254 * (h.volume() ** (1.0 / 3.0)) / L
        - 4.79323 * B / L
        - c1
    )
    # Soft wave term
    Cw = c1 * 0.02 * math.exp(m1 * Fn**d + 0.0 * math.cos(h.lcb_frac * math.pi))
    Cw = max(0.0, min(0.05, Cw * (1.0 + 2.0 * (Fn - 0.15) ** 2)))

    # Holtrop-Mennen bulb / transom terms (same formulas as the Zig HM1984 path).
    if h.abt_m2 > 0 or h.at_m2 > 0:
        from . import hm_appendages as hma

        cm = 0.98  # same C_M default as the Zig mapping
        cwp = max(0.55, min(0.99, (1.0 + 2.0 * Cb) / 3.0))
        qS = 0.5 * RHO_SW * U * U * S
        Cw = Cw * hma.c2(B, T, h.abt_m2, h.hb_m) * hma.c5(B, T, h.at_m2, cm)
        Cw += (hma.bulb_resistance(U, T, h.abt_m2, h.hb_m, RHO_SW, G)
               + hma.transom_resistance(U, B, cwp, h.at_m2, RHO_SW, G)) / qS

    Ca = 0.006 * (L + 100.0) ** -0.16 - 0.00205  # roughness allowance soft
    Ca = max(0.0, Ca)

    Ct = Cf * (1.0 + k1) + Cw + Ca
    Rt = 0.5 * RHO_SW * U * U * S * Ct
    return ResistanceResult(
        Fn=Fn,
        Rn=Rn,
        Cf=Cf,
        k1=k1,
        Cw=Cw,
        Rt_N=Rt,
        Ct=Ct,
        fidelity="simplified_py",
        notes=(
            "Exploratory HM-style estimate for ranking only; not ITTC powering claim."
        ),
    )


def residual_resistance_index(h: HullState) -> float:
    """Scalar for reward: Ct at design Fn (lower is better)."""
    return estimate_resistance(h).Ct
