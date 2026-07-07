#!/usr/bin/env python3
"""
Brutal dataset filter: oracle verify + dedup + reasoning quality gates.

Usage:
  python filter.py --input out/raw.jsonl --output out/train_filtered.jsonl
  python filter.py --input out/raw.jsonl --output out/train.jsonl --min-score 4
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "oracle"))
from yard_stability_oracle import Tank, WorkflowInput, evaluate_box_barge_workflow, to_answer_dict  # noqa: E402

REQUIRED_FORMULAS = [
    r"i_FS|i_fs|lb³/12|b\^3/12|b³/12",
    r"GG'|GG_prime|free.?surface",
    r"IMO|IS Code|2\.2",
    r"wall.?sided|Atwood|BM_T",
    r"GM₀|GM0|KM_T|metacentric",
]

REJECT_PATTERNS = [
    r"approximately\s+pass",  # hand-wavy
    r"I cannot",
    r"as an AI",
]


def reasoning_score(reasoning: str, has_tanks: bool) -> int:
    """0-5 rubric proxy. Keep records scoring >= 4."""
    score = 0
    hits = sum(1 for pat in REQUIRED_FORMULAS if re.search(pat, reasoning, re.I))
    score += min(hits, 3)  # formula citation
    if has_tanks and re.search(r"GG'|GG_prime|free.?surface", reasoning, re.I):
        score += 2
    elif not has_tanks:
        score += 1
    if re.search(r"B/\(2T\)|wall.?sided|assumption", reasoning, re.I):
        score += 1
    for pat in REJECT_PATTERNS:
        if re.search(pat, reasoning, re.I):
            score -= 2
    return max(0, min(5, score))


def verify_answer(record: dict, tol: float = 1e-4) -> bool:
    inp = record["input"]
    tanks = [Tank(**t) for t in inp.get("tanks", [])]
    out = evaluate_box_barge_workflow(WorkflowInput(
        L=inp["L"], B=inp["B"], T=inp["T"],
        kg_m=inp["kg_m"], tanks=tanks,
    ))
    recomputed = to_answer_dict(out)
    stored = record["answer"]

    for key in ("GM0", "GM_corrected", "GG_prime"):
        if abs(recomputed[key] - stored[key]) > tol:
            return False
    if recomputed["overall"] != stored["overall"]:
        return False
    for k, v in recomputed["imo_criteria"].items():
        if stored["imo_criteria"][k] != v:
            return False
    return True


def filter_dataset(
    input_path: Path,
    output_path: Path,
    min_score: int = 4,
    tol: float = 1e-4,
) -> dict:
    seen_hashes: set[str] = set()
    stats = {"total": 0, "kept": 0, "oracle_fail": 0, "dedup": 0, "rubric_fail": 0}

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with input_path.open() as fin, output_path.open("w") as fout:
        for line in fin:
            stats["total"] += 1
            rec = json.loads(line)

            if rec["id"] in seen_hashes:
                stats["dedup"] += 1
                continue

            if not verify_answer(rec, tol):
                stats["oracle_fail"] += 1
                continue

            has_tanks = bool(rec["input"].get("tanks"))
            if reasoning_score(rec["reasoning"], has_tanks) < min_score:
                stats["rubric_fail"] += 1
                continue

            seen_hashes.add(rec["id"])
            fout.write(json.dumps(rec) + "\n")
            stats["kept"] += 1

    return stats


def main() -> None:
    parser = argparse.ArgumentParser(description="Filter yard stability dataset")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--min-score", type=int, default=4)
    parser.add_argument("--tolerance", type=float, default=1e-4)
    args = parser.parse_args()

    stats = filter_dataset(args.input, args.output, args.min_score, args.tolerance)
    print(f"Filter results: {stats}")
    print(f"Kept {stats['kept']}/{stats['total']} ({100*stats['kept']/max(stats['total'],1):.1f}%)")


if __name__ == "__main__":
    main()