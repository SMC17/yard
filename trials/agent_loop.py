#!/usr/bin/env python3
"""Budgeted design-agent loop for the Yard Trials.

The benchmark contract: an agent gets the mission spec, a starting design,
and a hard budget of oracle calls (deterministic physics evaluations). Score
is the best gate-passing objective vector found within budget — sample
efficiency is the measured quantity, so report best-vs-calls, not just best.

Two proposers:
  --mode mock        seeded random hill-climb on the legal design space
                     (no network; CI-safe reference agent)
  --mode openrouter  an LLM proposes each next design from the mission,
                     the history, and the last physics report
                     (:free models only; OPENROUTER_API_KEY from env)

Physical consistency is enforced on every proposal regardless of proposer:
displacement and wetted surface are recomputed from the hull dimensions, so
an agent cannot self-declare a lighter, slipperier ship than its geometry.

Usage:
  python3 trials/agent_loop.py --mission sailmission/missions/m1-tea-race-1866/mission.json \
      --seed-design sailmission/missions/m1-tea-race-1866/submissions/cutty-sark-1869.json \
      --budget 12 [--mode mock] [--model deepseek/deepseek-chat-v3-0324:free] \
      [--trace trace.jsonl]
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import random
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Design variables the agent may set; everything else is recomputed or fixed.
MUTABLE = {
    ("hull", "loa_m"): (40.0, 95.0),
    ("hull", "beam_m"): (8.0, 18.0),
    ("hull", "draft_m"): (4.0, 9.0),
    ("hull", "depth_m"): (5.0, 12.0),
    ("hull", "cb"): (0.50, 0.80),
    ("hull", "kg_m"): (2.5, 6.0),
    ("rig", "area_m2"): (800.0, 6000.0),
}


def enforce_consistency(design: dict) -> dict:
    h = design["hull"]
    vol = h["loa_m"] * h["beam_m"] * h["draft_m"] * h["cb"]
    h["displacement_m3"] = round(vol, 1)
    # Denny-Mumford wetted-surface estimate from the same geometry.
    h["wetted_surface_m2"] = round(1.7 * h["loa_m"] * h["draft_m"] + vol / h["draft_m"], 1)
    return design


def evaluate(binary: Path, mission: Path, design: dict, workdir: Path) -> dict:
    sub_file = workdir / "candidate.json"
    sub_file.write_text(json.dumps(design, indent=2))
    proc = subprocess.run(
        [str(binary), "eval", str(mission), str(sub_file)],
        capture_output=True,
        text=True,
    )
    if proc.returncode not in (0, 2):
        raise RuntimeError(f"eval crashed: {proc.stderr}")
    return json.loads(proc.stdout)


def primary_score(report: dict) -> float | None:
    """First-objective value, direction-normalised to 'lower is better'."""
    if not report["scored"]:
        return None
    o = report["objectives"][0]
    return o["value"] if o["direction"] == "min" else -o["value"]


def mock_propose(rng: random.Random, best_design: dict) -> dict:
    d = copy.deepcopy(best_design)
    n_moves = rng.randint(1, 3)
    keys = rng.sample(sorted(MUTABLE), n_moves)
    for section, field in keys:
        lo, hi = MUTABLE[(section, field)]
        cur = d[section][field]
        step = (hi - lo) * rng.uniform(0.02, 0.10) * rng.choice([-1, 1])
        d[section][field] = round(min(hi, max(lo, cur + step)), 3)
    return enforce_consistency(d)


def openrouter_propose(model: str, mission_text: str, history: list[dict], best_design: dict) -> dict:
    if ":free" not in model:
        raise SystemExit("refusing non-free OpenRouter model (policy: :free only)")
    key = os.environ.get("OPENROUTER_API_KEY")
    if not key:
        raise SystemExit("OPENROUTER_API_KEY not set")
    recent = history[-4:]
    prompt = (
        "You are a naval architect competing in the Yard Trials. Mission spec:\n"
        f"{mission_text}\n\n"
        f"Current best design:\n{json.dumps(best_design, indent=1)}\n\n"
        "Recent evaluations (design changes -> objectives or gate failures):\n"
        + "\n".join(
            json.dumps(
                {
                    "objectives": r.get("objectives"),
                    "gates": {k: v for k, v in r.get("gates", {}).items() if k != "all_pass"},
                    "scored": r["scored"],
                }
            )
            for r in recent
        )
        + "\n\nPropose ONE improved submission JSON (same schema as the best design). "
        "Only change hull loa_m/beam_m/draft_m/depth_m/cb/kg_m and rig area_m2. "
        "Respond with the JSON object only."
    )
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=json.dumps(
            {
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.4,
            }
        ).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        content = json.load(resp)["choices"][0]["message"]["content"]
    start, end = content.find("{"), content.rfind("}")
    proposal = json.loads(content[start : end + 1])
    # The agent only steers the mutable variables; identity + physics are ours.
    d = copy.deepcopy(best_design)
    for section, field in MUTABLE:
        try:
            lo, hi = MUTABLE[(section, field)]
            d[section][field] = min(hi, max(lo, float(proposal[section][field])))
        except (KeyError, TypeError, ValueError):
            pass
    return enforce_consistency(d)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mission", type=Path, required=True)
    ap.add_argument("--seed-design", type=Path, required=True)
    ap.add_argument("--budget", type=int, default=12)
    ap.add_argument("--mode", choices=["mock", "openrouter"], default="mock")
    ap.add_argument("--model", default="deepseek/deepseek-chat-v3-0324:free")
    ap.add_argument("--rng-seed", type=int, default=1866)
    ap.add_argument("--trace", type=Path, default=None)
    args = ap.parse_args()

    module_dir = ROOT / "sailmission"
    subprocess.run(["zig", "build", "-Doptimize=ReleaseFast"], cwd=module_dir, check=True)
    binary = module_dir / "zig-out" / "bin" / "yard-sail-mission"
    workdir = Path(os.environ.get("TMPDIR", "/tmp"))

    mission_text = args.mission.read_text()
    rng = random.Random(args.rng_seed)

    best_design = enforce_consistency(json.loads(args.seed_design.read_text()))
    best_design["id"] = f"agent-{args.mode}"
    best_design["author"] = f"agent-loop/{args.mode}"

    history: list[dict] = []
    trace_lines: list[str] = []
    best_score: float | None = None
    best_report: dict | None = None
    rejected = 0

    for call in range(1, args.budget + 1):
        proposer = "baseline" if call == 1 else args.mode
        if call == 1:
            candidate = copy.deepcopy(best_design)  # baseline burn: know your start
        elif args.mode == "mock":
            candidate = mock_propose(rng, best_design)
        else:
            try:
                candidate = openrouter_propose(args.model, mission_text, history, best_design)
            except Exception as e:  # API hiccup: burn the call honestly via mock
                print(f"  [call {call}] API error ({type(e).__name__}); mock fallback")
                proposer = "mock-fallback"
                candidate = mock_propose(rng, best_design)

        report = evaluate(binary, args.mission, candidate, workdir)
        history.append(report)
        score = primary_score(report)
        if score is None:
            rejected += 1
        improved = score is not None and (best_score is None or score < best_score)
        if improved:
            best_score = score
            best_design = candidate
            best_report = report
        trace_lines.append(
            json.dumps(
                {
                    "call": call,
                    "proposer": proposer,
                    "scored": report["scored"],
                    "objectives": [o["value"] for o in report["objectives"]] if report["scored"] else None,
                    "improved": improved,
                    "design": {f"{s}.{f}": candidate[s][f] for s, f in MUTABLE},
                }
            )
        )
        status = f"{score:.2f}" if score is not None else "gate-rejected"
        print(f"call {call:>3}/{args.budget}: {status}" + ("  <- new best" if improved else ""))

    if args.trace:
        args.trace.write_text("".join(l + "\n" for l in trace_lines))

    print(f"\nbudget used: {args.budget} oracle calls, {rejected} gate rejections")
    if best_report is None:
        print("no gate-passing design found")
        return 2
    print("best objectives:", {o["id"]: round(o["value"], 3) for o in best_report["objectives"]})
    print("best design vars:", {f"{s}.{f}": best_design[s][f] for s, f in MUTABLE})
    return 0


if __name__ == "__main__":
    sys.exit(main())
