#!/usr/bin/env python3
"""
Generate oracle-verified SFT dataset for yard seakeeping assessment workflow.

Usage:
  python generate_seakeeping.py --samples 200 --output out/seakeeping_train.jsonl
  python generate_seakeeping.py --samples 50 --output out/seakeeping_eval.jsonl --split eval --seed 9999
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "oracle"))
from yard_seakeeping_oracle import (  # noqa: E402
    HeaveCoeffs,
    OperabilityLimits,
    SeaState,
    SeakeepingInput,
    default_barge_input,
    evaluate_seakeeping,
    to_answer_dict,
)

RHO = 1025.0
G = 9.80665

INSTRUCTION_TEMPLATES = [
    (
        "formal",
        "A box-barge has L={L:.0f} m, B={B:.0f} m, draft T={T:.1f} m. "
        "Sea state: Hs={Hs:.1f} m, Tz={Tz:.1f} s. "
        "Compute the ITTC modified PM wave spectrum, strip-theory heave RAO, "
        "response spectral moments, significant heave amplitude, and operability "
        "against limits (max heave {max_heave:.1f} m, max roll {max_roll:.0f}°). "
        "Report peak RAO, mean zero-crossing period, and validity flags.",
    ),
    (
        "conversational",
        "I've got a {L:.0f}×{B:.0f} m barge in {T:.1f} m draft. "
        "Waves are Hs={Hs:.1f} m with Tz={Tz:.1f} s. "
        "What's the significant heave? Will it exceed {max_heave:.1f} m heave "
        "or {max_roll:.0f}° roll limits?",
    ),
    (
        "exam",
        "EXAM (Seakeeping — spectral response):\n"
        "Box barge L={L:.0f} m, B={B:.0f} m, T={T:.1f} m.\n"
        "Sea: Hs={Hs:.1f} m, Tz={Tz:.1f} s.\n"
        "Required: (a) peak heave RAO and ω, (b) significant heave, "
        "(c) mean zero-crossing period, (d) operability pass/fail.",
    ),
]

REASONING_TEMPLATE = """\
Step 1 — Principal particulars & heave coefficients:
  V = L×B×T = {L:.0f}×{B:.0f}×{T:.1f} = {V:.0f} m³
  C_33 = ρ g A_w = {C_33:.2e} N/m
  M = ρV = {M:.0f} kg, A_33 = {A_33:.0f} kg

Step 2 — ITTC modified PM spectrum S(ω) on ω ∈ [{wmin:.1f}, {wmax:.1f}] rad/s:
  Build |H(ω)| from strip-theory heave RAO
  Peak RAO = {peak_rao:.4f} m/m @ ω = {peak_omega:.2f} rad/s

Step 3 — Response spectrum S_R(ω) = |H|² S(ω):
  m₀ (response) = {m0_resp:.4f} m²·s
  Significant heave H_s,R = 4√m₀ = {sig_heave:.4f} m
  Mean zero-crossing T_z = 2π√(m₀/m₂) = {tz:.2f} s

Step 4 — Operability check:
  Max heave (RK4 harmonic @ peak ω) = {max_heave:.4f} m
  Max roll = {max_roll:.2f}°
  Limits: heave ≤ {max_heave_lim:.1f} m, roll ≤ {max_roll_lim:.0f}°
  Operability: {op_pass}

Step 5 — Validity flags: {flags}
"""


def make_record(inp: SeakeepingInput, style: str, split: str) -> dict:
    out = evaluate_seakeeping(inp)
    answer = to_answer_dict(out)
    V = inp.L * inp.B * inp.T

    tmpl = next(t for s, t in INSTRUCTION_TEMPLATES if s == style)
    instruction = tmpl.format(
        L=inp.L, B=inp.B, T=inp.T,
        Hs=inp.sea.Hs_m, Tz=inp.sea.Tz_s,
        max_heave=inp.limits.max_heave_m,
        max_roll=inp.limits.max_roll_deg,
    )

    reasoning = REASONING_TEMPLATE.format(
        L=inp.L, B=inp.B, T=inp.T, V=V,
        C_33=inp.heave.C_33, M=inp.heave.M_kg, A_33=inp.heave.A_33,
        wmin=inp.omega_min, wmax=inp.omega_max,
        peak_rao=out.stats.peak_rao, peak_omega=out.stats.peak_omega_rad_s,
        m0_resp=out.stats.m0_response,
        sig_heave=out.stats.significant_heave_m,
        tz=out.stats.mean_zero_crossing_period_s,
        max_heave=out.simulation.max_heave_m,
        max_roll=answer["max_roll_deg"],
        max_heave_lim=inp.limits.max_heave_m,
        max_roll_lim=inp.limits.max_roll_deg,
        op_pass="PASS" if out.simulation.operability_pass else "FAIL",
        flags=", ".join(out.flags),
    )

    payload = json.dumps(
        {
            "L": inp.L, "B": inp.B, "T": inp.T,
            "Hs_m": inp.sea.Hs_m, "Tz_s": inp.sea.Tz_s,
            "limits": {"max_heave_m": inp.limits.max_heave_m, "max_roll_deg": inp.limits.max_roll_deg},
        },
        sort_keys=True,
    )
    record_id = hashlib.sha256(f"{payload}:{style}".encode()).hexdigest()[:16]

    return {
        "id": record_id,
        "instruction": instruction,
        "reasoning": reasoning,
        "answer": answer,
        "input": {
            "L": inp.L, "B": inp.B, "T": inp.T,
            "Hs_m": inp.sea.Hs_m, "Tz_s": inp.sea.Tz_s,
            "limits": {
                "max_heave_m": inp.limits.max_heave_m,
                "max_roll_deg": inp.limits.max_roll_deg,
            },
        },
        "verification": {
            "source": "yard-seakeeping-oracle-v0.1",
            "tolerance": 0.02,
            "zig_module": "yard/compose/seakeeping_assessment",
        },
        "metadata": {
            "instruction_style": style,
            "difficulty": "canonical" if inp.L == 100.0 and inp.sea.Hs_m == 2.0 else "random",
            "split": split,
            "workflow": "seakeeping",
        },
    }


def sample_input(rng: random.Random, *, canonical: bool = False) -> SeakeepingInput:
    if canonical:
        return default_barge_input()

    L = rng.uniform(60.0, 150.0)
    B = rng.uniform(12.0, 22.0)
    T = rng.uniform(4.0, 8.0)
    Hs = rng.uniform(1.0, 4.0)
    Tz = rng.uniform(5.0, 12.0)
    V = L * B * T
    Aw = L * B
    C_33 = RHO * G * Aw

    return SeakeepingInput(
        L=L, B=B, T=T,
        sea=SeaState(Hs_m=Hs, Tz_s=Tz),
        heave=HeaveCoeffs(
            M_kg=RHO * V,
            A_33=rng.uniform(0.1, 0.3) * RHO * V,
            B_33=rng.uniform(3.0e5, 8.0e5),
            C_33=C_33,
            F_mag=C_33,
        ),
        limits=OperabilityLimits(
            max_heave_m=rng.uniform(1.5, 3.0),
            max_roll_deg=rng.uniform(10.0, 20.0),
        ),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate yard seakeeping SFT dataset")
    parser.add_argument("--samples", type=int, default=100)
    parser.add_argument("--output", type=Path, default=Path("out/seakeeping_train.jsonl"))
    parser.add_argument("--split", default="train", choices=["train", "val", "eval", "gap-audit"])
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    args.output.parent.mkdir(parents=True, exist_ok=True)

    styles = [s for s, _ in INSTRUCTION_TEMPLATES]
    seen_ids: set[str] = set()
    written = 0

    with args.output.open("w") as f:
        rec = make_record(sample_input(rng, canonical=True), "formal", args.split)
        f.write(json.dumps(rec) + "\n")
        seen_ids.add(rec["id"])
        written += 1

        while written < args.samples:
            inp = sample_input(rng)
            style = rng.choice(styles)
            rec = make_record(inp, style, args.split)
            if rec["id"] in seen_ids:
                continue
            seen_ids.add(rec["id"])
            f.write(json.dumps(rec) + "\n")
            written += 1

    print(f"Wrote {written} records to {args.output}")


if __name__ == "__main__":
    main()