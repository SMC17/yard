"""Parametric hull state, hydrostatics, and L0 feasibility constraints."""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass, field
from typing import Any

RHO_SW = 1025.0
G = 9.80665

# Soft bands for preliminary box-like / high-Cb exploratory hulls (L0 only).
CB_MIN, CB_MAX = 0.45, 0.95
TB_MIN, TB_MAX = 0.15, 0.55  # T/B
LB_MIN, LB_MAX = 3.0, 12.0  # L/B
GM_MIN = 0.15  # m, mirrors IS Code GM0 floor for reward shaping
LCB_FRAC_MIN, LCB_FRAC_MAX = -0.05, 0.05  # fraction of L from midship aft(-)/fwd(+)


@dataclass
class HullState:
    """Particulars for a box-like exploratory hull (Cb scales displacement)."""

    L: float = 120.0
    B: float = 20.0
    T: float = 8.0
    Cb: float = 0.75
    lcb_frac: float = 0.0  # LCB as fraction of L from midship
    kg_frac: float = 0.55  # KG / D approximation using D≈1.25*T
    Fn: float = 0.20

    def volume(self) -> float:
        return self.L * self.B * self.T * self.Cb

    def displacement_t(self) -> float:
        return self.volume() * RHO_SW / 1000.0

    def kb(self) -> float:
        return 0.5 * self.T  # box-like

    def bm_t(self) -> float:
        v = self.volume()
        if v <= 0:
            return 0.0
        # waterplane ~ L*B for high-Cb; scale by approx Cw≈Cb^0.5 soft
        i_t = self.L * self.B**3 / 12.0
        return i_t / v

    def depth_approx(self) -> float:
        return max(self.T * 1.25, self.T + 0.5)

    def kg(self) -> float:
        return self.kg_frac * self.depth_approx()

    def km_t(self) -> float:
        return self.kb() + self.bm_t()

    def gm0(self) -> float:
        return self.km_t() - self.kg()

    def lcb_m(self) -> float:
        return self.lcb_frac * self.L

    def wetted_approx(self) -> float:
        # Guldhammer-Harvald-ish box approximation
        return self.L * (2.0 * self.T + self.B) * (0.9 + 0.1 * self.Cb)

    def as_vector(self) -> list[float]:
        return [self.L, self.B, self.T, self.Cb, self.lcb_frac, self.kg_frac, self.Fn]

    @classmethod
    def from_vector(cls, v: list[float] | tuple[float, ...]) -> "HullState":
        return cls(
            L=float(v[0]),
            B=float(v[1]),
            T=float(v[2]),
            Cb=float(v[3]),
            lcb_frac=float(v[4]),
            kg_frac=float(v[5]),
            Fn=float(v[6]) if len(v) > 6 else 0.20,
        )

    def clamp_soft(self) -> "HullState":
        h = HullState(**asdict(self))
        h.L = max(20.0, min(400.0, h.L))
        h.B = max(4.0, min(70.0, h.B))
        h.T = max(1.0, min(30.0, h.T))
        h.Cb = max(0.35, min(0.98, h.Cb))
        h.lcb_frac = max(-0.08, min(0.08, h.lcb_frac))
        h.kg_frac = max(0.35, min(0.75, h.kg_frac))
        h.Fn = max(0.10, min(0.35, h.Fn))
        return h

    def to_dict(self) -> dict[str, Any]:
        return {
            **asdict(self),
            "volume_m3": self.volume(),
            "displacement_t": self.displacement_t(),
            "kb_m": self.kb(),
            "bm_t_m": self.bm_t(),
            "km_t_m": self.km_t(),
            "gm0_m": self.gm0(),
            "lcb_m": self.lcb_m(),
            "wetted_m2": self.wetted_approx(),
            "L_B": self.L / self.B if self.B else math.inf,
            "T_B": self.T / self.B if self.B else math.inf,
        }


@dataclass
class L0Report:
    feasible: bool
    violations: list[str] = field(default_factory=list)
    metrics: dict[str, float] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "feasible": self.feasible,
            "violations": list(self.violations),
            "metrics": dict(self.metrics),
        }


def evaluate_l0(h: HullState) -> L0Report:
    """Algebraic / hydrostatic feasibility — reject before L1 resistance."""
    vios: list[str] = []
    if h.L <= 0 or h.B <= 0 or h.T <= 0:
        vios.append("non_positive_particulars")
    if h.volume() <= 0:
        vios.append("non_positive_volume")
    lb = h.L / h.B if h.B else math.inf
    tb = h.T / h.B if h.B else math.inf
    if not (LB_MIN <= lb <= LB_MAX):
        vios.append(f"L_B_out_of_band:{lb:.3f}")
    if not (TB_MIN <= tb <= TB_MAX):
        vios.append(f"T_B_out_of_band:{tb:.3f}")
    if not (CB_MIN <= h.Cb <= CB_MAX):
        vios.append(f"Cb_out_of_band:{h.Cb:.3f}")
    if not (LCB_FRAC_MIN <= h.lcb_frac <= LCB_FRAC_MAX):
        vios.append(f"lcb_frac_out_of_band:{h.lcb_frac:.4f}")
    gm = h.gm0()
    if gm < GM_MIN:
        vios.append(f"gm0_below_floor:{gm:.3f}")
    # wall-sided-ish envelope for box GM model honesty
    if h.B / (2.0 * h.T) <= 0.8:
        vios.append("hydrostatic_model_outside_envelope")
    metrics = {
        "L_B": lb,
        "T_B": tb,
        "Cb": h.Cb,
        "gm0_m": gm,
        "volume_m3": h.volume(),
        "displacement_t": h.displacement_t(),
    }
    return L0Report(feasible=len(vios) == 0, violations=vios, metrics=metrics)
