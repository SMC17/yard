#!/usr/bin/env python3
"""
Run fine-tuned or base Ollama model on eval set, produce predictions JSONL for harness.

Usage:
  python infer_ollama.py --model yard-stability-v1 --dataset ../dataset/out/eval.jsonl \
    --output ../gap_audit/out/preds.jsonl
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "gap_audit"))
from gap_audit import extract_json, ollama_generate, SYSTEM_PROMPT  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description="Ollama inference for eval harness")
    parser.add_argument("--model", required=True)
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--host", default="http://127.0.0.1:11434")
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    count = 0

    with args.dataset.open() as fin, args.output.open("w") as fout:
        for line in fin:
            if args.limit and count >= args.limit:
                break
            rec = json.loads(line)
            raw, _ = ollama_generate(args.model, rec["instruction"], args.host)
            pred = extract_json(raw) or {}
            fout.write(json.dumps({"id": rec["id"], "prediction": pred, "raw": raw[:1000]}) + "\n")
            count += 1
            print(f"  [{count}] {rec['id'][:8]}…", flush=True)

    print(f"Wrote {count} predictions to {args.output}")


if __name__ == "__main__":
    main()