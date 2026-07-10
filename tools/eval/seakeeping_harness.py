#!/usr/bin/env python3
"""Score seakeeping eval JSONL against oracle regeneration."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "oracle"))
from yard_seakeeping_oracle import (  # noqa: E402
    HeaveCoeffs,
    OperabilityLimits,
    SeaState,
    SeakeepingInput,
    evaluate_seakeeping,
)

YARD_ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, required=True)
    args = parser.parse_args()

    records = []
    with args.dataset.open() as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))

    mismatches = 0
    for row in records:
        inp = row.get("input", {})
        expected = row.get("answer", {})
        L = float(inp.get("L", inp.get("length", 100)))
        B = float(inp.get("B", inp.get("beam", 16)))
        T = float(inp.get("T", inp.get("draft", 6)))
        Hs = float(inp.get("Hs", inp.get("Hs_m", 2)))
        Tz = float(inp.get("Tz", inp.get("Tz_s", 8)))
        rho = 1025.0
        vol = L * B * T * 0.65
        M = vol * rho
        Aw = L * B
        actual = evaluate_seakeeping(
            SeakeepingInput(
                L=L,
                B=B,
                T=T,
                sea=SeaState(Hs_m=Hs, Tz_s=Tz),
                heave=HeaveCoeffs(A33=0.2 * M, B33=5.0e5),
                limits=OperabilityLimits(
                    max_heave_m=float(expected.get("max_heave_m", 3.0)),
                    max_roll_deg=float(expected.get("max_roll_deg", 15)),
                ),
            )
        )
        exp_sig = expected.get("significant_heave_m")
        if exp_sig is not None:
            if abs(actual.stats.significant_heave_m - float(exp_sig)) > 0.05:
                mismatches += 1

    print(f"Seakeeping dataset: {len(records)} records, mismatches={mismatches}")
    return 1 if mismatches > len(records) * 0.1 else 0


if __name__ == "__main__":
    raise SystemExit(main())