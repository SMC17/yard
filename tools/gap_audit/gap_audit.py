#!/usr/bin/env python3
"""
Gap audit: probe models on held-out stability cases, catalog failure modes.

Compares model structured output against yard-stability-oracle ground truth.
Works with Ollama (local), OpenAI-compatible APIs, or --baseline naive solver.

Usage:
  python gap_audit.py --dataset ../dataset/out/eval.jsonl --model qwen2.5:7b
  python gap_audit.py --dataset ../dataset/out/eval.jsonl --baseline naive
  python gap_audit.py --dataset ../dataset/out/eval.jsonl --model qwen2.5:7b --output out/gap_report.jsonl
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).parent.parent / "oracle"))
from yard_stability_oracle import (  # noqa: E402
    Tank,
    WorkflowInput,
    evaluate_box_barge_workflow,
    to_answer_dict,
)

SYSTEM_PROMPT = """You are a naval architecture stability engineer.
Given a box-barge stability problem, compute GM0, apply free-surface correction
for any slack tanks, evaluate IMO 2008 IS Code Part A 2.2 criteria, and respond
with ONLY a JSON object (no markdown fences) containing:
{
  "GM0": <float>,
  "GM_corrected": <float>,
  "GG_prime": <float>,
  "GZ_at_30": <float>,
  "imo_criteria": {
    "area_0_30": "PASS"|"FAIL",
    "area_0_40": "PASS"|"FAIL",
    "area_30_40": "PASS"|"FAIL",
    "gz_at_30": "PASS"|"FAIL",
    "angle_gz_max": "PASS"|"FAIL",
    "gm_0": "PASS"|"FAIL"
  },
  "overall": "PASS"|"FAIL",
  "flags": ["wall_sided_assumption_valid", "free_surface_applied", ...]
}
Show your work mentally but output only the JSON."""

FAILURE_MODES = [
    "omitted_free_surface",
    "wrong_gm_formula",
    "small_angle_instead_wall_sided",
    "wrong_is_code_threshold",
    "no_assumption_flags",
    "json_parse_failure",
    "numerical_drift",
    "overall_criteria_mismatch",
]


@dataclass
class AuditResult:
    id: str
    model: str
    oracle_overall: str
    model_overall: str | None
    gm0_error: float | None
    gm_corr_error: float | None
    criteria_matches: int
    criteria_total: int = 6
    flags_ok: bool = False
    failure_modes: list[str] = field(default_factory=list)
    raw_response: str = ""
    latency_s: float = 0.0


def oracle_from_record(record: dict) -> dict:
    inp = record["input"]
    tanks = [Tank(**t) for t in inp.get("tanks", [])]
    out = evaluate_box_barge_workflow(WorkflowInput(
        L=inp["L"], B=inp["B"], T=inp["T"],
        kg_m=inp["kg_m"], tanks=tanks,
    ))
    return to_answer_dict(out)


def extract_json(text: str) -> dict | None:
    text = text.strip()
    # Strip markdown fences if present
    text = re.sub(r"^```(?:json)?\s*", "", text)
    text = re.sub(r"\s*```$", "", text)
    # Find first JSON object
    start = text.find("{")
    if start < 0:
        return None
    depth = 0
    for i, ch in enumerate(text[start:], start):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(text[start : i + 1])
                except json.JSONDecodeError:
                    return None
    return None


def classify_failures(oracle: dict, predicted: dict | None, raw: str) -> list[str]:
    modes: list[str] = []
    if predicted is None:
        modes.append("json_parse_failure")
        return modes

    inp_has_tanks = oracle.get("flags") and "free_surface_applied" in oracle["flags"]
    pred_flags = predicted.get("flags", [])
    pred_gg = predicted.get("GG_prime", 0)

    if inp_has_tanks and pred_gg < 0.01:
        modes.append("omitted_free_surface")
    if inp_has_tanks and "free_surface_applied" not in pred_flags:
        modes.append("no_assumption_flags")

    gm0 = predicted.get("GM0")
    gm_corr = predicted.get("GM_corrected")
    if gm0 is not None and gm_corr is not None:
        if abs(gm0 - gm_corr) < 1e-6 and inp_has_tanks:
            modes.append("omitted_free_surface")
        if gm_corr is not None and oracle.get("GM_corrected"):
            rel = abs(gm_corr - oracle["GM_corrected"]) / max(abs(oracle["GM_corrected"]), 1e-9)
            if rel > 0.05:
                modes.append("numerical_drift")
            # GM_corr ≈ GM0 suggests wall-sided/small-angle confusion with no FS
            if abs(gm_corr - oracle["GM0"]) < 0.02 and inp_has_tanks:
                modes.append("small_angle_instead_wall_sided")

    criteria = predicted.get("imo_criteria", {})
    oracle_criteria = oracle.get("imo_criteria", {})
    mismatches = sum(
        1 for k, v in oracle_criteria.items()
        if criteria.get(k) != v
    )
    if mismatches > 0:
        modes.append("wrong_is_code_threshold")
    if predicted.get("overall") != oracle.get("overall"):
        modes.append("overall_criteria_mismatch")

    return list(dict.fromkeys(modes))  # dedupe preserve order


def score_prediction(oracle: dict, predicted: dict | None) -> AuditResult:
    """Partial result; caller fills id/model/raw."""
    if predicted is None:
        return AuditResult(
            id="", model="",
            oracle_overall=oracle["overall"],
            model_overall=None,
            gm0_error=None, gm_corr_error=None,
            criteria_matches=0,
            failure_modes=["json_parse_failure"],
        )

    gm0_err = abs(predicted.get("GM0", 0) - oracle["GM0"]) if "GM0" in predicted else None
    gm_corr_err = (
        abs(predicted.get("GM_corrected", 0) - oracle["GM_corrected"])
        if "GM_corrected" in predicted else None
    )
    criteria_matches = sum(
        1 for k, v in oracle["imo_criteria"].items()
        if predicted.get("imo_criteria", {}).get(k) == v
    )
    flags_ok = set(predicted.get("flags", [])) >= set(oracle.get("flags", []))

    return AuditResult(
        id="", model="",
        oracle_overall=oracle["overall"],
        model_overall=predicted.get("overall"),
        gm0_error=gm0_err,
        gm_corr_error=gm_corr_err,
        criteria_matches=criteria_matches,
        flags_ok=flags_ok,
        failure_modes=classify_failures(oracle, predicted, ""),
    )


# --- Baseline solvers simulating common frontier-model failure modes ---


def naive_solver_no_fs(record: dict) -> dict:
    """Simulates: computes GM0, skips free-surface, uses small-angle GZ."""
    inp = record["input"]
    L, B, T, kg = inp["L"], inp["B"], inp["T"], inp["kg_m"]
    V = L * B * T
    km_t = T / 2 + (L * B**3 / 12) / V
    gm0 = km_t - kg
    # "Model forgets FS correction"
    gm_corr = gm0
    # Small-angle GZ at 30°
    gz_30 = gm_corr * math.sin(math.radians(30))
    return {
        "GM0": round(gm0, 4),
        "GM_corrected": round(gm_corr, 4),
        "GG_prime": 0.0,
        "GZ_at_30": round(gz_30, 4),
        "imo_criteria": {k: "PASS" for k in [
            "area_0_30", "area_0_40", "area_30_40",
            "gz_at_30", "angle_gz_max", "gm_0",
        ]},
        "overall": "PASS",
        "flags": ["wall_sided_assumption_valid"],
    }


def naive_solver_wrong_threshold(record: dict) -> dict:
    """Simulates: correct GM but wrong IS Code thresholds."""
    ans = oracle_from_record(record)
    # Wrong: uses GM0 for criteria but reports corrected GM
    ans["imo_criteria"] = {k: "PASS" for k in ans["imo_criteria"]}
    ans["overall"] = "PASS"
    return ans


BASELINES: dict[str, Callable[[dict], dict]] = {
    "naive_no_fs": naive_solver_no_fs,
    "naive_overconfident": naive_solver_wrong_threshold,
}


def ollama_generate(model: str, prompt: str, host: str = "http://127.0.0.1:11434") -> tuple[str, float]:
    payload = json.dumps({
        "model": model,
        "prompt": f"{SYSTEM_PROMPT}\n\n{prompt}",
        "stream": False,
        "options": {"temperature": 0.1, "num_predict": 1024},
    }).encode()
    req = urllib.request.Request(
        f"{host}/api/generate",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=300) as resp:
        data = json.loads(resp.read())
    return data.get("response", ""), time.time() - t0


def run_audit(
    dataset_path: Path,
    *,
    model: str | None = None,
    baseline: str | None = None,
    limit: int | None = None,
    host: str = "http://127.0.0.1:11434",
) -> list[AuditResult]:
    results: list[AuditResult] = []
    with dataset_path.open() as f:
        records = [json.loads(line) for line in f]
    if limit:
        records = records[:limit]

    for rec in records:
        oracle = oracle_from_record(rec)
        raw = ""
        latency = 0.0

        if baseline:
            predicted = BASELINES[baseline](rec)
            model_name = f"baseline:{baseline}"
        elif model:
            try:
                raw, latency = ollama_generate(model, rec["instruction"], host)
                predicted = extract_json(raw)
            except (urllib.error.URLError, TimeoutError) as e:
                predicted = None
                raw = str(e)
                model_name = model
            else:
                model_name = model
        else:
            raise ValueError("Specify --model or --baseline")

        ar = score_prediction(oracle, predicted)
        ar.id = rec["id"]
        ar.model = model_name
        ar.raw_response = raw[:2000]
        ar.latency_s = latency
        ar.failure_modes = classify_failures(oracle, predicted, raw)
        ar.oracle_overall = oracle["overall"]
        results.append(ar)

    return results


def summarize(results: list[AuditResult]) -> str:
    n = len(results)
    if n == 0:
        return "No results."
    overall_match = sum(1 for r in results if r.model_overall == r.oracle_overall)
    gm0_ok = sum(1 for r in results if r.gm0_error is not None and r.gm0_error < 0.02)
    gm_corr_ok = sum(1 for r in results if r.gm_corr_error is not None and r.gm_corr_error < 0.02)
    criteria_perfect = sum(1 for r in results if r.criteria_matches == 6)
    flags_ok = sum(1 for r in results if r.flags_ok)

    mode_counts: dict[str, int] = {}
    for r in results:
        for m in r.failure_modes:
            mode_counts[m] = mode_counts.get(m, 0) + 1

    lines = [
        f"=== Gap Audit Summary ({results[0].model}) ===",
        f"Cases:              {n}",
        f"Overall match:      {overall_match}/{n} ({100*overall_match/n:.1f}%)",
        f"GM₀ within 2cm:     {gm0_ok}/{n}",
        f"GM_corr within 2cm: {gm_corr_ok}/{n}",
        f"All 6 criteria:     {criteria_perfect}/{n}",
        f"Flags superset:     {flags_ok}/{n}",
        "",
        "Failure mode catalog:",
    ]
    for mode, count in sorted(mode_counts.items(), key=lambda x: -x[1]):
        lines.append(f"  {mode}: {count}/{n} ({100*count/n:.1f}%)")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Yard stability gap audit")
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--model", default=None, help="Ollama model name")
    parser.add_argument("--baseline", choices=list(BASELINES.keys()), default=None)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--host", default="http://127.0.0.1:11434")
    args = parser.parse_args()

    results = run_audit(
        args.dataset,
        model=args.model,
        baseline=args.baseline,
        limit=args.limit,
        host=args.host,
    )
    print(summarize(results))

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("w") as f:
            for r in results:
                f.write(json.dumps(asdict(r)) + "\n")
        print(f"\nWrote {len(results)} results to {args.output}")


if __name__ == "__main__":
    main()