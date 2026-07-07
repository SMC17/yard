#!/usr/bin/env python3
"""
Custom eval harness for yard stability fine-tuning.

Scores model outputs against the Python oracle (which mirrors Zig ground truth).

Usage:
  # Oracle baseline (sanity check — should score 100%)
  python harness.py --dataset ../dataset/out/eval.jsonl --mode oracle

  # Score a model output file (JSONL with 'prediction' field)
  python harness.py --dataset eval.jsonl --predictions preds.jsonl --mode model
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "oracle"))
from yard_stability_oracle import (  # noqa: E402
    Tank,
    WorkflowInput,
    evaluate_box_barge_workflow,
    to_answer_dict,
)


@dataclass
class ScoreBreakdown:
    total: int = 0
    overall_match: int = 0
    gm0_within_tol: int = 0
    gm_corr_within_tol: int = 0
    criteria_exact: int = 0
    flags_overlap: int = 0
    numerical_errors: list[float] = field(default_factory=list)

    def report(self) -> str:
        if self.total == 0:
            return "No records scored."
        lines = [
            f"Records:           {self.total}",
            f"Overall PASS/FAIL: {self.overall_match}/{self.total} ({100*self.overall_match/self.total:.1f}%)",
            f"GM₀ within tol:    {self.gm0_within_tol}/{self.total} ({100*self.gm0_within_tol/self.total:.1f}%)",
            f"GM_corr within tol:{self.gm_corr_within_tol}/{self.total} ({100*self.gm_corr_within_tol/self.total:.1f}%)",
            f"All 6 criteria:    {self.criteria_exact}/{self.total} ({100*self.criteria_exact/self.total:.1f}%)",
            f"Flags overlap:     {self.flags_overlap}/{self.total} ({100*self.flags_overlap/self.total:.1f}%)",
        ]
        if self.numerical_errors:
            med = sorted(self.numerical_errors)[len(self.numerical_errors) // 2]
            lines.append(f"Median GM₀ error:  {med:.6f} m")
        return "\n".join(lines)


def oracle_answer(record: dict) -> dict:
    inp_data = record["input"]
    tanks = [Tank(**t) for t in inp_data.get("tanks", [])]
    inp = WorkflowInput(
        L=inp_data["L"], B=inp_data["B"], T=inp_data["T"],
        kg_m=inp_data["kg_m"], tanks=tanks,
    )
    out = evaluate_box_barge_workflow(inp)
    return to_answer_dict(out)


def within_tol(predicted: float, expected: float, tol: float = 0.01) -> bool:
    if expected == 0:
        return abs(predicted) < tol
    return abs(predicted - expected) / abs(expected) < tol or abs(predicted - expected) < tol


def score_record(expected: dict, predicted: dict, tol: float) -> dict:
    scores = {
        "overall_match": expected["overall"] == predicted.get("overall"),
        "gm0_ok": within_tol(predicted.get("GM0", 0), expected["GM0"], tol),
        "gm_corr_ok": within_tol(predicted.get("GM_corrected", 0), expected["GM_corrected"], tol),
        "criteria_ok": all(
            predicted.get("imo_criteria", {}).get(k) == v
            for k, v in expected["imo_criteria"].items()
        ),
        "flags_ok": set(predicted.get("flags", [])) >= set(expected["flags"]),
    }
    scores["pass"] = all(scores.values())
    return scores


def run_oracle_mode(dataset_path: Path, tol: float) -> ScoreBreakdown:
    """Re-compute oracle from inputs; verify dataset integrity."""
    breakdown = ScoreBreakdown()
    with dataset_path.open() as f:
        for line in f:
            record = json.loads(line)
            breakdown.total += 1
            recomputed = oracle_answer(record)
            stored = record["answer"]

            s = score_record(stored, recomputed, tol)
            if s["overall_match"]:
                breakdown.overall_match += 1
            if s["gm0_ok"]:
                breakdown.gm0_within_tol += 1
            if s["gm_corr_ok"]:
                breakdown.gm_corr_within_tol += 1
            if s["criteria_ok"]:
                breakdown.criteria_exact += 1
            if s["flags_ok"]:
                breakdown.flags_overlap += 1
            breakdown.numerical_errors.append(abs(recomputed["GM0"] - stored["GM0"]))
    return breakdown


def run_model_mode(dataset_path: Path, predictions_path: Path, tol: float) -> ScoreBreakdown:
    breakdown = ScoreBreakdown()
    preds: dict[str, dict] = {}
    with predictions_path.open() as f:
        for line in f:
            rec = json.loads(line)
            preds[rec["id"]] = rec.get("prediction", rec.get("answer", {}))

    with dataset_path.open() as f:
        for line in f:
            record = json.loads(line)
            breakdown.total += 1
            expected = oracle_answer(record)
            predicted = preds.get(record["id"], {})
            s = score_record(expected, predicted, tol)
            if s["overall_match"]:
                breakdown.overall_match += 1
            if s["gm0_ok"]:
                breakdown.gm0_within_tol += 1
            if s["gm_corr_ok"]:
                breakdown.gm_corr_within_tol += 1
            if s["criteria_ok"]:
                breakdown.criteria_exact += 1
            if s["flags_ok"]:
                breakdown.flags_overlap += 1
            if "GM0" in predicted:
                breakdown.numerical_errors.append(abs(predicted["GM0"] - expected["GM0"]))
    return breakdown


def main() -> None:
    parser = argparse.ArgumentParser(description="Yard stability eval harness")
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--predictions", type=Path, default=None)
    parser.add_argument("--mode", choices=["oracle", "model"], default="oracle")
    parser.add_argument("--tolerance", type=float, default=0.01)
    args = parser.parse_args()

    if args.mode == "oracle":
        result = run_oracle_mode(args.dataset, args.tolerance)
    else:
        if not args.predictions:
            parser.error("--predictions required for model mode")
        result = run_model_mode(args.dataset, args.predictions, args.tolerance)

    print(result.report())


if __name__ == "__main__":
    main()