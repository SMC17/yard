#!/usr/bin/env python3
"""
Benchmark oracle-grounded agent on held-out eval set.

Compares extraction modes: regex, ollama, hybrid, record_input (upper bound).

Usage:
  python eval_oracle_agent.py --dataset tools/dataset/out/eval.jsonl --limit 30
  python eval_oracle_agent.py --dataset tools/dataset/out/eval.jsonl --modes ollama hybrid
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "gap_audit"))
sys.path.insert(0, str(Path(__file__).parent))

from extract_spec import extract_spec  # noqa: E402
from gap_audit import classify_failures, oracle_from_record, score_prediction, summarize  # noqa: E402
from oracle_agent import run_oracle_agent  # noqa: E402


def eval_mode(
    dataset: Path,
    mode: str,
    limit: int | None,
    *,
    ollama_model: str,
    ollama_host: str,
) -> tuple[str, float]:
    results = []
    errors = 0
    t0 = time.time()

    lines = [l for l in dataset.read_text().splitlines() if l.strip()]
    if limit:
        lines = lines[:limit]

    for idx, line in enumerate(lines, 1):
        rec = json.loads(line)
        if mode in ("ollama", "hybrid"):
            print(f"  [{mode}] {idx}/{len(lines)} {rec['id'][:8]}…", flush=True)
        oracle = oracle_from_record(rec)

        if mode == "record_input":
            spec = rec["input"]
            extraction_notes: list[str] = []
            extraction_mode = "record_input"
        else:
            try:
                spec, extraction_notes, extraction_mode = extract_spec(
                    rec["instruction"],
                    mode=mode,  # type: ignore[arg-type]
                    model=ollama_model,
                    host=ollama_host,
                )
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
            extraction_mode=extraction_mode,
            extraction_notes=extraction_notes,
        )
        predicted = artifact.answer
        ar = score_prediction(oracle, predicted)
        ar.id = rec["id"]
        ar.model = f"oracle_agent/{mode}"
        ar.failure_modes = classify_failures(oracle, predicted, "")
        results.append(ar)

    elapsed = time.time() - t0
    summary = summarize(results)
    header = (
        f"=== Oracle Agent Eval ({mode}) ===\n"
        f"Extraction failures: {errors}\n"
        f"Elapsed: {elapsed:.1f}s ({elapsed / max(len(lines), 1):.2f}s/case)\n"
    )
    return header + summary, elapsed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", type=Path, required=True)
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument(
        "--modes",
        nargs="+",
        default=["regex", "ollama", "hybrid", "record_input"],
        choices=["regex", "ollama", "hybrid", "record_input"],
    )
    ap.add_argument("--ollama-model", default="qwen2.5-coder:1.5b")
    ap.add_argument("--ollama-host", default="http://127.0.0.1:11434")
    ap.add_argument("--output", type=Path, default=None)
    args = ap.parse_args()

    parts: list[str] = []
    for mode in args.modes:
        text, _ = eval_mode(
            args.dataset,
            mode,
            args.limit,
            ollama_model=args.ollama_model,
            ollama_host=args.ollama_host,
        )
        parts.append(text)
        parts.append("")

    report = "\n".join(parts)
    print(report)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())