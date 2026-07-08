#!/usr/bin/env python3
"""yard-damage-oracle — mirrors compose/damage_stability.zig."""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from yard_stability_oracle import (  # noqa: E402
    RHO_SEAWATER,
    Tank,
    WorkflowInput,
    effective_gm,
    evaluate_box_barge_workflow,
    evaluate_is_code,
    rect_tank_ifs,
    small_angle_gz,
    wall_sided_gz,
)


@dataclass
class DamageInput:
    L: float
    B: float
    T: float
    kg_m: float
    l_lost_m: float
    depth_m: float
    mu: float = 1.0
    tanks: list[Tank] = field(default_factory=list)


@dataclass
class DamageOutput:
    t_damaged_m: float
    gm0_intact_m: float
    gm_corr_intact_m: float
    gm0_damaged_m: float
    gm_corr_damaged_m: float
    is_code_overall: str
    flags: list[str]


def box_barge_t_damaged(L: float, l_lost: float, T_intact: float, D: float, mu: float) -> float:
    if not (0.0 <= mu <= 1.0):
        raise ValueError("invalid permeability")
    if l_lost >= L or L <= 0 or T_intact <= 0 or D <= 0:
        raise ValueError("invalid dimensions")
    t_d = T_intact * L / (L - mu * l_lost)
    if t_d >= D:
        raise ValueError("flooding exceeds hull depth")
    return t_d


def evaluate_damage(inp: DamageInput) -> DamageOutput:
    intact = evaluate_box_barge_workflow(
        WorkflowInput(L=inp.L, B=inp.B, T=inp.T, kg_m=inp.kg_m, tanks=inp.tanks)
    )

    t_d = box_barge_t_damaged(inp.L, inp.l_lost_m, inp.T, inp.depth_m, inp.mu)
    L_rem = inp.L - inp.l_lost_m
    V_d = L_rem * inp.B * t_d
    kb = t_d / 2.0
    i_t = L_rem * inp.B**3 / 12.0
    bm_t = i_t / V_d
    km_t = kb + bm_t
    gm0 = km_t - inp.kg_m

    gg = 0.0
    for t in inp.tanks:
        i_fs = rect_tank_ifs(t.l_m, t.b_m)
        gg += (t.rho_fluid / RHO_SEAWATER) * i_fs / V_d
    gm_corr = gm0 - gg

    wall_sided = (inp.B / (2.0 * t_d)) > 1.0
    angles, gz = [], []
    deg = 0.0
    while deg <= 40.0 + 1e-9:
        rad = math.radians(deg)
        angles.append(rad)
        gz.append(
            wall_sided_gz(gm_corr, bm_t, rad)
            if wall_sided
            else small_angle_gz(gm_corr, rad)
        )
        deg += 5.0

    ic = evaluate_is_code(angles, gz, gm0)
    flags = ["data_insufficient"]
    if wall_sided:
        flags.append("wall_sided_assumption_valid")
    if inp.tanks:
        flags.append("free_surface_applied")
    if gm_corr < 0.15:
        flags.append("outside_validity_envelope")

    return DamageOutput(
        t_damaged_m=t_d,
        gm0_intact_m=intact.gm0_m,
        gm_corr_intact_m=intact.gm_corrected_m,
        gm0_damaged_m=gm0,
        gm_corr_damaged_m=gm_corr,
        is_code_overall=ic.overall.value,
        flags=flags,
    )


def to_answer_dict(out: DamageOutput) -> dict:
    return {
        "T_damaged_m": round(out.t_damaged_m, 6),
        "GM0_intact_m": round(out.gm0_intact_m, 6),
        "GM_corrected_intact_m": round(out.gm_corr_intact_m, 6),
        "GM0_damaged_m": round(out.gm0_damaged_m, 6),
        "GM_corrected_damaged_m": round(out.gm_corr_damaged_m, 6),
        "overall": out.is_code_overall,
        "flags": out.flags,
    }


if __name__ == "__main__":
    import json

    out = evaluate_damage(
        DamageInput(L=10.0, B=4.0, T=1.5, kg_m=1.0, l_lost_m=2.0, depth_m=3.0)
    )
    print(json.dumps(to_answer_dict(out), indent=2))