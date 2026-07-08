#!/usr/bin/env python3
"""Score model predictions against oracle on any stability eval set."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(Path(__file__).parent.parent / "oracle"))

from gap_audit import classify_failures, oracle_from_record, score_prediction, summarize  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", type=Path, required=True)
    ap.add_argument("--predictions", type=Path, required=True)
    ap.add_argument("--model-name", default="custom")
    ap.add_argument("--output", type=Path, default=None)
    args = ap.parse_args()

    records = {json.loads(l)["id"]: json.loads(l) for l in args.dataset.read_text().splitlines() if l.strip()}
    preds = [json.loads(l) for l in args.predictions.read_text().splitlines() if l.strip()]

    results = []
    for p in preds:
        rec = records.get(p["id"])
        if not rec:
            continue
        oracle = oracle_from_record(rec)
        predicted = p.get("prediction") or None
        if predicted == {}:
            predicted = None
        ar = score_prediction(oracle, predicted)
        ar.id = p["id"]
        ar.model = args.model_name
        ar.failure_modes = classify_failures(oracle, predicted, p.get("raw", ""))
        ar.oracle_overall = oracle["overall"]
        results.append(ar)

    summary = summarize(results)
    print(summary)

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(summary + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())