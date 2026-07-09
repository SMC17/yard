#!/usr/bin/env python3
"""
Benchmark oracle-grounded agent on held-out eval set.

Compares:
  - oracle_agent (regex extract → oracle) — Physical AI path
  - record_input oracle (upper bound; skips NL parse errors)

Usage:
  python eval_oracle_agent.py --dataset tools/dataset/out/eval.jsonl
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "gap_audit"))
sys.path.insert(0, str(Path(__file__).parent))

from gap_audit import classify_failures, oracle_from_record, score_prediction, summarize  # noqa: E402
from oracle_agent import extract_spec_from_instruction, run_oracle_agent  # noqa: E402


def eval_mode(dataset: Path, mode: str, limit: int | None) -> str:
    results = []
    errors = 0
    for i, line in enumerate(dataset.read_text().splitlines()):
        if not line.strip():
            continue
        if limit and i >= limit:
            break
        rec = json.loads(line)
        oracle = oracle_from_record(rec)

        if mode == "record_input":
            spec = rec["input"]
            extraction_notes: list[str] = []
        else:
            try:
                spec, extraction_notes = extract_spec_from_instruction(rec["instruction"])
            except ValueError:
                errors += 1
                ar = score_prediction(oracle, None)
                ar.id = rec["id"]
                ar.model = f"oracle_agent/{mode}"
                ar.failure_modes = ["json_parse_failure", "extraction_failure"]
                results.append(ar)
                continue

        artifact = run_oracle_agent(
            query=rec["instruction"],
            spec=spec,
            extraction_mode=mode,
            extraction_notes=extraction_notes,
        )
        predicted = artifact.answer
        ar = score_prediction(oracle, predicted)
        ar.id = rec["id"]
        ar.model = f"oracle_agent/{mode}"
        ar.failure_modes = classify_failures(oracle, predicted, "")
        results.append(ar)

    summary = summarize(results)
    header = f"=== Oracle Agent Eval ({mode}) ===\nExtraction failures: {errors}\n"
    return header + summary


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", type=Path, required=True)
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--output", type=Path, default=None)
    args = ap.parse_args()

    parts = [
        eval_mode(args.dataset, "instruction_regex", args.limit),
        "",
        eval_mode(args.dataset, "record_input", args.limit),
    ]
    text = "\n".join(parts)
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())