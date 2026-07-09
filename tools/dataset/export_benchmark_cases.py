#!/usr/bin/env python3
"""
Export benchmark harness cases to JSONL for eval / fine-tune flywheel.

Runs `zig build run-benchmark` logic via subprocess and parses stdout, or
reads pre-generated report JSON if present.

Usage:
  python export_benchmark_cases.py --output out/benchmark_eval.jsonl
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

YARD_ROOT = Path(__file__).resolve().parents[2]


def run_harness() -> str:
    proc = subprocess.run(
        ["zig", "build", "run-benchmark"],
        cwd=YARD_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return proc.stdout


def parse_report(stdout: str) -> list[dict]:
    cases: list[dict] = []
    for line in stdout.splitlines():
        line = line.strip()
        if not line.startswith("[PASS]") and not line.startswith("[FAIL]"):
            continue
        status, rest = line.split("]", 1)
        status = status.strip("[").strip()
        parts = [p.strip() for p in rest.split("/")]
        if len(parts) < 3:
            continue
        hull, case_name, metric = parts[0], parts[1], parts[2]
        cases.append(
            {
                "instruction": (
                    f"Validate benchmark case {case_name} for {hull}: "
                    f"report metric {metric} with proof level cross_validated."
                ),
                "input": {"hull": hull, "case": case_name, "metric": metric},
                "answer": {"verdict": status, "pass": status == "PASS"},
                "metadata": {"source": "yard-benchmark-harness", "lane": "naval-sim"},
            }
        )
    return cases


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    stdout = run_harness()
    cases = parse_report(stdout)
    if not cases:
        print("No cases parsed from harness output", file=sys.stderr)
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w") as f:
        for row in cases:
            f.write(json.dumps(row) + "\n")

    print(f"Wrote {len(cases)} benchmark eval cases to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())