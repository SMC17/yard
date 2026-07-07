#!/usr/bin/env python3
"""
Generate oracle-verified SFT dataset for yard stability / IMO IS Code 2.2.

Usage:
  python generate.py --samples 500 --output out/train.jsonl
  python generate.py --samples 50 --output out/eval.jsonl --split eval
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import sys
from pathlib import Path

# Add oracle to path
sys.path.insert(0, str(Path(__file__).parent.parent / "oracle"))
from yard_stability_oracle import (  # noqa: E402
    Tank,
    WorkflowInput,
    evaluate_box_barge_workflow,
    to_answer_dict,
)

INSTRUCTION_TEMPLATES = [
    (
        "formal",
        "A rectangular box-barge has L={L:.1f} m, B={B:.1f} m, draft T={T:.2f} m. "
        "KG = {kg:.3f} m above keel. {tank_desc}"
        "Compute GM₀, apply free-surface correction, build a wall-sided GZ curve "
        "to 40°, and evaluate IMO 2008 IS Code Part A 2.2 criteria. "
        "Report pass/fail with margins and flag any violated assumptions.",
    ),
    (
        "conversational",
        "I've got a box barge — {L:.0f} m long, {B:.0f} m beam, {T:.1f} m draft. "
        "Center of gravity is {kg:.2f} m above the keel. {tank_desc}"
        "Can you check intact stability? I need GM, the free-surface effect, "
        "and whether it passes the six IS Code 2008 criteria.",
    ),
    (
        "exam",
        "EXAM QUESTION (Naval Architecture — Intact Stability):\n"
        "Box barge: LPP = {L:.1f} m, B = {B:.1f} m, T = {T:.2f} m, KG = {kg:.3f} m.\n"
        "{tank_desc}"
        "Required: (a) GM₀ and corrected GM, (b) GZ at 30°, "
        "(c) all six IMO IS Code 2008 Part A 2.2 criteria with PASS/FAIL.",
    ),
    (
        "checklist",
        "Stability review checklist — box barge\n"
        "□ L={L:.1f}m B={B:.1f}m T={T:.2f}m KG={kg:.3f}m\n"
        "{tank_desc}"
        "□ Compute GM₀ → free-surface correction → wall-sided GZ\n"
        "□ Evaluate IS Code 2.2 (areas, GZ@30°, angle of max GZ, GM₀)\n"
        "□ Flag assumption violations",
    ),
]

REASONING_TEMPLATE = """\
Step 1 — Hydrostatics (rectangular box-barge, closed form):
  V = L × B × T = {L:.1f} × {B:.1f} × {T:.2f} = {V:.2f} m³
  KB = T/2 = {KB:.4f} m
  BM_T = (L × B³/12) / V = {BM_T:.4f} m
  KM_T = KB + BM_T = {KM_T:.4f} m

Step 2 — Initial metacentric height:
  GM₀ = KM_T − KG = {KM_T:.4f} − {kg:.3f} = {GM0:.4f} m

Step 3 — Free-surface correction:
{tank_reasoning}
  GG' = {GG_prime:.4f} m
  GM_corrected = GM₀ − GG' = {GM_corr:.4f} m

Step 4 — Assumption check:
  B/(2T) = {b_over_2t:.2f} → wall-sided {wall_sided_status}
  {fs_status}

Step 5 — GZ curve (wall-sided Atwood):
  GZ(φ) = (GM + 0.5·BM_T·tan²φ)·sinφ
  GZ at 30° = {GZ_at_30:.4f} m

Step 6 — IMO IS Code 2008 Part A 2.2:
  Area 0–30°:  {area_0_30:.4f} m·rad  (≥ 0.055) → {v_area_0_30}
  Area 0–40°:  {area_0_40:.4f} m·rad  (≥ 0.090) → {v_area_0_40}
  Area 30–40°: {area_30_40:.4f} m·rad (≥ 0.030) → {v_area_30_40}
  GZ at 30°:   {GZ_at_30:.4f} m       (≥ 0.200) → {v_gz_at_30}
  Angle GZ_max: {angle_max:.1f}°       (≥ 25°)   → {v_angle_max}
  GM₀:         {GM0:.4f} m            (≥ 0.150) → {v_gm_0}
  OVERALL: {overall}
"""


def tank_description(tanks: list[Tank]) -> str:
    if not tanks:
        return "No slack tanks. "
    parts = []
    for i, t in enumerate(tanks, 1):
        fluid = "fresh water" if abs(t.rho_fluid - 1000) < 1 else f"ρ={t.rho_fluid:.0f} kg/m³"
        parts.append(f"Tank {i}: {t.l_m:.1f} × {t.b_m:.1f} m ({fluid}). ")
    return "".join(parts)


def tank_reasoning(tanks: list[Tank], V: float, gg_prime: float) -> str:
    if not tanks:
        return "  No tanks → GG' = 0\n"
    lines = []
    total = 0.0
    for i, t in enumerate(tanks, 1):
        i_fs = t.l_m * t.b_m**3 / 12.0
        contrib = (t.rho_fluid / 1025.0) * i_fs / V
        total += contrib
        lines.append(
            f"  Tank {i}: i_FS = {t.l_m:.1f}×{t.b_m:.1f}³/12 = {i_fs:.2f} m⁴, "
            f"GG'ᵢ = ({t.rho_fluid}/1025)×{i_fs:.2f}/{V:.1f} = {contrib:.4f} m"
        )
    lines.append(f"  Total GG' = {total:.4f} m")
    return "\n".join(lines) + "\n"


def make_record(
    inp: WorkflowInput,
    style: str,
    split: str,
    rng: random.Random,
) -> dict:
    out = evaluate_box_barge_workflow(inp)
    answer = to_answer_dict(out)
    ic = out.is_code

    tmpl = next(t for s, t in INSTRUCTION_TEMPLATES if s == style)
    instruction = tmpl.format(
        L=inp.L, B=inp.B, T=inp.T, kg=inp.kg_m,
        tank_desc=tank_description(inp.tanks),
    )

    reasoning = REASONING_TEMPLATE.format(
        L=inp.L, B=inp.B, T=inp.T, kg=inp.kg_m, V=out.hydrostatics.volume_m3,
        KB=out.hydrostatics.kb_m, BM_T=out.hydrostatics.bm_t_m,
        KM_T=out.hydrostatics.km_t_m, GM0=out.gm0_m,
        GG_prime=out.gg_prime_m, GM_corr=out.gm_corrected_m,
        tank_reasoning=tank_reasoning(inp.tanks, out.hydrostatics.volume_m3, out.gg_prime_m),
        b_over_2t=inp.B / (2 * inp.T),
        wall_sided_status="valid" if out.wall_sided_valid else "NOT valid; using small-angle",
        fs_status="✓ free_surface_applied" if inp.tanks else "✓ no tanks — no free-surface correction",
        GZ_at_30=ic.values["gz_at_30"],
        area_0_30=ic.values["area_0_30"],
        area_0_40=ic.values["area_0_40"],
        area_30_40=ic.values["area_30_40"],
        angle_max=ic.values["angle_gz_max_deg"],
        v_area_0_30=ic.area_0_30.value,
        v_area_0_40=ic.area_0_40.value,
        v_area_30_40=ic.area_30_40.value,
        v_gz_at_30=ic.gz_at_30.value,
        v_angle_max=ic.angle_gz_max.value,
        v_gm_0=ic.gm_0.value,
        overall=ic.overall.value,
    )

    payload = json.dumps(
        {"L": inp.L, "B": inp.B, "T": inp.T, "kg_m": inp.kg_m,
         "tanks": [{"l_m": t.l_m, "b_m": t.b_m, "rho_fluid": t.rho_fluid} for t in inp.tanks]},
        sort_keys=True,
    )
    record_id = hashlib.sha256(f"{payload}:{style}".encode()).hexdigest()[:16]

    return {
        "id": record_id,
        "instruction": instruction,
        "reasoning": reasoning,
        "answer": answer,
        "input": {
            "L": inp.L, "B": inp.B, "T": inp.T, "kg_m": inp.kg_m,
            "tanks": [{"l_m": t.l_m, "b_m": t.b_m, "rho_fluid": t.rho_fluid} for t in inp.tanks],
        },
        "verification": {
            "source": "yard-stability-oracle-v0.1",
            "tolerance": 1e-6,
            "zig_module": "yard/stability + yard/hydro",
        },
        "metadata": {
            "instruction_style": style,
            "difficulty": "canonical" if inp.L == 10.0 else "random",
            "split": split,
        },
    }


def sample_input(rng: random.Random, *, canonical: bool = False) -> WorkflowInput:
    if canonical:
        return WorkflowInput(
            L=10.0, B=4.0, T=1.5, kg_m=1.0,
            tanks=[Tank(l_m=5.0, b_m=3.0)],
        )

    L = rng.uniform(8.0, 40.0)
    B = rng.uniform(3.0, 12.0)
    T = rng.uniform(1.0, 4.0)
    # Keep KG below KM for stability
    km_approx = 0.5 * T + (L * B**3 / 12) / (L * B * T)
    kg = rng.uniform(0.3 * km_approx, 0.85 * km_approx)

    tanks: list[Tank] = []
    if rng.random() < 0.6:
        n_tanks = rng.randint(0, 2)
        for _ in range(n_tanks):
            tanks.append(Tank(
                l_m=rng.uniform(2.0, 0.5 * L),
                b_m=rng.uniform(1.0, 0.5 * B),
                rho_fluid=rng.choice([1000.0, 1025.0, 850.0]),
            ))

    return WorkflowInput(L=L, B=B, T=T, kg_m=kg, tanks=tanks)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate yard stability SFT dataset")
    parser.add_argument("--samples", type=int, default=100)
    parser.add_argument("--output", type=Path, default=Path("out/train.jsonl"))
    parser.add_argument("--split", default="train", choices=["train", "val", "eval", "gap-audit"])
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    args.output.parent.mkdir(parents=True, exist_ok=True)

    styles = [s for s, _ in INSTRUCTION_TEMPLATES]
    seen_ids: set[str] = set()
    written = 0

    with args.output.open("w") as f:
        # Always include canonical fixture
        rec = make_record(sample_input(rng, canonical=True), "formal", args.split, rng)
        f.write(json.dumps(rec) + "\n")
        seen_ids.add(rec["id"])
        written += 1

        while written < args.samples:
            inp = sample_input(rng)
            style = rng.choice(styles)
            rec = make_record(inp, style, args.split, rng)
            if rec["id"] in seen_ids:
                continue
            seen_ids.add(rec["id"])
            f.write(json.dumps(rec) + "\n")
            written += 1

    print(f"Wrote {written} records to {args.output}")


if __name__ == "__main__":
    main()