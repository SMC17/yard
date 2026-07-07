#!/usr/bin/env python3
"""
Export filtered JSONL to HuggingFace/Unsloth chat format.

Usage:
  python export_sft.py --input out/train_filtered.jsonl --output out/train_chat.jsonl
  python export_sft.py --input out/train_filtered.jsonl --output out/train_alpaca.jsonl --format alpaca
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def to_chat(record: dict) -> dict:
    answer_json = json.dumps(record["answer"], indent=2)
    return {
        "id": record["id"],
        "messages": [
            {"role": "system", "content": (
                "You are a naval architecture stability engineer. Compute GM0, "
                "apply free-surface correction, evaluate IMO 2008 IS Code Part A 2.2, "
                "and report structured results with assumption flags."
            )},
            {"role": "user", "content": record["instruction"]},
            {"role": "assistant", "content": (
                f"{record['reasoning']}\n\n```json\n{answer_json}\n```"
            )},
        ],
        "metadata": record.get("metadata", {}),
    }


def to_alpaca(record: dict) -> dict:
    answer_json = json.dumps(record["answer"], indent=2)
    return {
        "id": record["id"],
        "instruction": record["instruction"],
        "input": "",
        "output": f"{record['reasoning']}\n\n{answer_json}",
        "metadata": record.get("metadata", {}),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Export SFT training format")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--format", choices=["chat", "alpaca"], default="chat")
    args = parser.parse_args()

    converter = to_chat if args.format == "chat" else to_alpaca
    args.output.parent.mkdir(parents=True, exist_ok=True)

    count = 0
    with args.input.open() as fin, args.output.open("w") as fout:
        for line in fin:
            rec = json.loads(line)
            fout.write(json.dumps(converter(rec)) + "\n")
            count += 1

    print(f"Exported {count} records to {args.output} ({args.format} format)")


if __name__ == "__main__":
    main()