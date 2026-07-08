#!/usr/bin/env python3
"""
Export JSON-only chat format — assistant outputs ONLY structured JSON.

Matches infer_local.py SYSTEM_PROMPT (no CoT). Fixes train/infer mismatch
that caused 60% json_parse_failure on smoke eval.

Usage:
  python export_json_only.py --input out/train.jsonl --output out/train_chat_json_only.jsonl
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

SYSTEM = (
    "You are a naval architecture stability engineer. "
    "Given a box-barge stability problem, compute GM0, apply free-surface correction "
    "for any slack tanks, evaluate IMO 2008 IS Code Part A 2.2 criteria, and respond "
    "with ONLY a JSON object (no markdown fences) containing: "
    '{"GM0", "GM_corrected", "GG_prime", "GZ_at_30", "imo_criteria", "overall", "flags"}.'
)


def to_json_only_chat(record: dict) -> dict:
    answer_json = json.dumps(record["answer"], separators=(",", ":"))
    return {
        "id": record["id"],
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": record["instruction"]},
            {"role": "assistant", "content": answer_json},
        ],
        "metadata": {**record.get("metadata", {}), "format": "json_only"},
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--tank-weight", type=int, default=1,
                    help="Repeat records with tanks N times (free-surface emphasis)")
    args = ap.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    tank_dupes = 0
    with args.input.open() as fin, args.output.open("w") as fout:
        for line in fin:
            if args.limit and count >= args.limit:
                break
            rec = json.loads(line)
            has_tanks = bool(rec.get("input", {}).get("tanks"))
            reps = args.tank_weight if has_tanks else 1
            for _ in range(reps):
                fout.write(json.dumps(to_json_only_chat(rec)) + "\n")
                count += 1
                if has_tanks and reps > 1:
                    tank_dupes += 1
            if not args.limit:
                continue
            if count >= args.limit:
                break
    print(f"Exported {count} JSON-only records to {args.output} (tank dupes: {tank_dupes})")


if __name__ == "__main__":
    main()