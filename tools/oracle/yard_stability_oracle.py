#!/usr/bin/env python3
"""
yard-stability-oracle — Python reference implementation mirroring yard/stability Zig.

Ground truth for dataset generation and eval harness. All formulas trace to:
  - stability/src/gz.zig
  - stability/src/is_code.zig
  - hydro/src/box_barge.zig (for BM_T, KM_T)

Tolerance target: 1e-6 relative for analytical cases.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum
from typing import Sequence


RHO_SEAWATER = 1025.0
RHO_FRESHWATER = 1000.0
G = 9.80665

DEG30 = math.radians(30.0)
DEG40 = math.radians(40.0)


class Verdict(str, Enum):
    PASS = "PASS"
    FAIL = "FAIL"


class ValidityFlag(str, Enum):
    WALL_SIDED_VALID = "wall_sided_assumption_valid"
    FREE_SURFACE_APPLIED = "free_surface_applied"
    SMALL_ANGLE_REGIME = "small_angle_regime"
    OUTSIDE_ENVELOPE = "outside_validity_envelope"
    DATA_INSUFFICIENT = "data_insufficient"


@dataclass
class Tank:
    l_m: float
    b_m: float
    rho_fluid: float = RHO_FRESHWATER


@dataclass
class BoxBargeHydrostatics:
    L: float
    B: float
    T: float
    volume_m3: float = 0.0
    kb_m: float = 0.0
    bm_t_m: float = 0.0
    km_t_m: float = 0.0
    c_b: float = 1.0

    def compute(self) -> None:
        self.volume_m3 = self.L * self.B * self.T
        self.kb_m = 0.5 * self.T
        self.bm_t_m = (self.L * self.B**3 / 12.0) / self.volume_m3
        self.km_t_m = self.kb_m + self.bm_t_m
        self.c_b = 1.0


# --- GZ primitives (mirror gz.zig) ---


def small_angle_gz(gm: float, phi_rad: float) -> float:
    return gm * math.sin(phi_rad)


def wall_sided_gz(gm: float, bm_t: float, phi_rad: float) -> float:
    tan_phi = math.tan(phi_rad)
    return (gm + 0.5 * bm_t * tan_phi * tan_phi) * math.sin(phi_rad)


def rect_tank_ifs(l_m: float, b_m: float) -> float:
    return l_m * b_m**3 / 12.0


def fs_contribution(rho_fluid: float, rho_seawater: float, i_fs: float, v_disp: float) -> float:
    return (rho_fluid / rho_seawater) * i_fs / v_disp


def effective_gm(gm: float, tanks: Sequence[Tank], rho_seawater: float, v_disp: float) -> tuple[float, float]:
    """Returns (gm_corrected, gg_prime)."""
    gg_prime = 0.0
    for t in tanks:
        i_fs = rect_tank_ifs(t.l_m, t.b_m)
        gg_prime += fs_contribution(t.rho_fluid, rho_seawater, i_fs, v_disp)
    return gm - gg_prime, gg_prime


# --- IS Code 2.2 (mirror is_code.zig) ---


def _trapezoid_area(angles: Sequence[float], gz: Sequence[float], lo: float, hi: float) -> float:
    area = 0.0
    for i in range(len(angles) - 1):
        a0, a1 = angles[i], angles[i + 1]
        if a1 <= lo or a0 >= hi:
            continue
        l = max(a0, lo)
        h = min(a1, hi)
        dx = h - l
        if a1 == a0:
            t0, t1 = 0.0, 1.0
        else:
            t0 = (l - a0) / (a1 - a0)
            t1 = (h - a0) / (a1 - a0)
        gz0 = gz[i] + t0 * (gz[i + 1] - gz[i])
        gz1 = gz[i] + t1 * (gz[i + 1] - gz[i])
        area += 0.5 * (gz0 + gz1) * dx
    return area


def _interp_at(angles: Sequence[float], gz: Sequence[float], target: float) -> float:
    for i in range(len(angles) - 1):
        if angles[i] <= target <= angles[i + 1]:
            t = (target - angles[i]) / (angles[i + 1] - angles[i])
            return gz[i] + t * (gz[i + 1] - gz[i])
    return gz[-1]


def _angle_of_max_gz_deg(angles: Sequence[float], gz: Sequence[float]) -> float:
    i_max = max(range(len(gz)), key=lambda i: gz[i])
    return math.degrees(angles[i_max])


@dataclass
class IsCodeResult:
    area_0_30: Verdict
    area_0_40: Verdict
    area_30_40: Verdict
    gz_at_30: Verdict
    angle_gz_max: Verdict
    gm_0: Verdict
    overall: Verdict
    values: dict = field(default_factory=dict)


def evaluate_is_code(angles_rad: Sequence[float], gz: Sequence[float], gm_0: float) -> IsCodeResult:
    if len(angles_rad) < 3 or len(angles_rad) != len(gz):
        raise ValueError("InsufficientSamples")
    for i in range(len(angles_rad) - 1):
        if angles_rad[i + 1] <= angles_rad[i]:
            raise ValueError("AnglesNotMonotonic")

    area_0_30 = _trapezoid_area(angles_rad, gz, 0.0, DEG30)
    area_0_40 = _trapezoid_area(angles_rad, gz, 0.0, DEG40)
    area_30_40 = _trapezoid_area(angles_rad, gz, DEG30, DEG40)
    gz_at_30 = _interp_at(angles_rad, gz, DEG30)
    angle_gz_max = _angle_of_max_gz_deg(angles_rad, gz)

    values = {
        "area_0_30": area_0_30,
        "area_0_40": area_0_40,
        "area_30_40": area_30_40,
        "gz_at_30": gz_at_30,
        "angle_gz_max_deg": angle_gz_max,
        "gm_0": gm_0,
    }

    v = {
        "area_0_30": Verdict.PASS if area_0_30 >= 0.055 else Verdict.FAIL,
        "area_0_40": Verdict.PASS if area_0_40 >= 0.090 else Verdict.FAIL,
        "area_30_40": Verdict.PASS if area_30_40 >= 0.030 else Verdict.FAIL,
        "gz_at_30": Verdict.PASS if gz_at_30 >= 0.200 else Verdict.FAIL,
        "angle_gz_max": Verdict.PASS if angle_gz_max >= 25.0 else Verdict.FAIL,
        "gm_0": Verdict.PASS if gm_0 >= 0.150 else Verdict.FAIL,
    }
    overall = Verdict.PASS if all(x == Verdict.PASS for x in v.values()) else Verdict.FAIL

    return IsCodeResult(
        area_0_30=v["area_0_30"],
        area_0_40=v["area_0_40"],
        area_30_40=v["area_30_40"],
        gz_at_30=v["gz_at_30"],
        angle_gz_max=v["angle_gz_max"],
        gm_0=v["gm_0"],
        overall=overall,
        values=values,
    )


# --- Full workflow ---


@dataclass
class WorkflowInput:
    L: float
    B: float
    T: float
    kg_m: float
    tanks: list[Tank] = field(default_factory=list)
    max_heel_deg: float = 40.0
    heel_step_deg: float = 5.0
    rho_seawater: float = RHO_SEAWATER


@dataclass
class WorkflowOutput:
    hydrostatics: BoxBargeHydrostatics
    gm0_m: float
    gm_corrected_m: float
    gg_prime_m: float
    gz_curve: list[dict]
    is_code: IsCodeResult
    flags: list[ValidityFlag]
    wall_sided_valid: bool


def evaluate_box_barge_workflow(inp: WorkflowInput) -> WorkflowOutput:
    hydro = BoxBargeHydrostatics(L=inp.L, B=inp.B, T=inp.T)
    hydro.compute()

    gm0 = hydro.km_t_m - inp.kg_m
    gm_corr, gg_prime = effective_gm(gm0, inp.tanks, inp.rho_seawater, hydro.volume_m3)

    wall_sided_valid = (inp.B / (2.0 * inp.T)) > 1.0

    flags: list[ValidityFlag] = []
    if wall_sided_valid:
        flags.append(ValidityFlag.WALL_SIDED_VALID)
    if inp.tanks:
        flags.append(ValidityFlag.FREE_SURFACE_APPLIED)
    if inp.max_heel_deg <= 10.0:
        flags.append(ValidityFlag.SMALL_ANGLE_REGIME)

    angles_rad: list[float] = []
    gz_vals: list[float] = []
    gz_curve: list[dict] = []

    deg = 0.0
    while deg <= inp.max_heel_deg + 1e-9:
        rad = math.radians(deg)
        angles_rad.append(rad)
        gz_m = (
            wall_sided_gz(gm_corr, hydro.bm_t_m, rad)
            if wall_sided_valid
            else small_angle_gz(gm_corr, rad)
        )
        gz_vals.append(gz_m)
        gz_curve.append({"angle_deg": deg, "angle_rad": rad, "gz_m": gz_m})
        deg += inp.heel_step_deg

    is_code = evaluate_is_code(angles_rad, gz_vals, gm0)

    return WorkflowOutput(
        hydrostatics=hydro,
        gm0_m=gm0,
        gm_corrected_m=gm_corr,
        gg_prime_m=gg_prime,
        gz_curve=gz_curve,
        is_code=is_code,
        flags=flags,
        wall_sided_valid=wall_sided_valid,
    )


def to_answer_dict(out: WorkflowOutput) -> dict:
    """Structured answer block for dataset JSONL."""
    ic = out.is_code
    return {
        "GM0": round(out.gm0_m, 6),
        "GM_corrected": round(out.gm_corrected_m, 6),
        "GG_prime": round(out.gg_prime_m, 6),
        "KB": round(out.hydrostatics.kb_m, 6),
        "BM_T": round(out.hydrostatics.bm_t_m, 6),
        "KM_T": round(out.hydrostatics.km_t_m, 6),
        "GZ_at_30": round(ic.values["gz_at_30"], 6),
        "imo_criteria": {
            "area_0_30": ic.area_0_30.value,
            "area_0_40": ic.area_0_40.value,
            "area_30_40": ic.area_30_40.value,
            "gz_at_30": ic.gz_at_30.value,
            "angle_gz_max": ic.angle_gz_max.value,
            "gm_0": ic.gm_0.value,
        },
        "overall": ic.overall.value,
        "flags": [f.value for f in out.flags],
    }


# --- Self-test against validation fixtures ---


def _self_test() -> None:
    inp = WorkflowInput(
        L=10.0, B=4.0, T=1.5, kg_m=1.0,
        tanks=[Tank(l_m=5.0, b_m=3.0)],
    )
    out = evaluate_box_barge_workflow(inp)

    assert abs(out.gm0_m - 0.6389) < 0.002, f"GM0: {out.gm0_m}"
    assert abs(out.gg_prime_m - 0.183) < 0.01, f"GG': {out.gg_prime_m}"
    assert abs(out.gm_corrected_m - 0.456) < 0.01, f"GM_corr: {out.gm_corrected_m}"

    # GZ@10° with free-surface-corrected GM (~0.456 m), not uncorrected GM
    gz_10 = next(s for s in out.gz_curve if s["angle_deg"] == 10.0)
    assert abs(gz_10["gz_m"] - 0.0816) < 0.002, f"GZ@10 (corrected): {gz_10['gz_m']}"

    # Uncorrected GM case (no tanks)
    out_bare = evaluate_box_barge_workflow(
        WorkflowInput(L=10.0, B=4.0, T=1.5, kg_m=1.0, tanks=[])
    )
    gz_10_bare = next(s for s in out_bare.gz_curve if s["angle_deg"] == 10.0)
    assert abs(gz_10_bare["gz_m"] - 0.1134) < 0.002, f"GZ@10 (bare): {gz_10_bare['gz_m']}"

    print("oracle self-test: PASS")


if __name__ == "__main__":
    _self_test()