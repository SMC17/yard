#!/usr/bin/env python3
"""
Score benchmark eval JSONL (from export_benchmark_cases.py).

Usage:
  python benchmark_harness.py --dataset ../dataset/out/benchmark_eval.jsonl
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

YARD_ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, required=True)
    args = parser.parse_args()

    proc = subprocess.run(
        ["zig", "build", "run-benchmark"],
        cwd=YARD_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    harness_pass = "ALL PASS" in proc.stdout

    records = []
    with args.dataset.open() as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))

    expected_pass = sum(1 for r in records if r.get("answer", {}).get("pass"))
    total = len(records)

    print(f"Benchmark harness: {'PASS' if harness_pass else 'FAIL'}")
    print(f"Dataset records:     {total}")
    print(f"Dataset pass flags:  {expected_pass}/{total}")
    if not harness_pass:
        print(proc.stdout[-2000:], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())