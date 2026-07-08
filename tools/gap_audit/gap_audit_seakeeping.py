#!/usr/bin/env python3
"""
Gap audit for seakeeping workflow — probe models vs yard-seakeeping-oracle.

Usage:
  python gap_audit_seakeeping.py --dataset ../dataset/out/seakeeping_eval.jsonl --baseline naive
  python gap_audit_seakeeping.py --dataset ../dataset/out/seakeeping_eval.jsonl --model qwen2.5-coder:1.5b --n 50
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field, asdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "oracle"))
from yard_seakeeping_oracle import (  # noqa: E402
    HeaveCoeffs,
    OperabilityLimits,
    SeaState,
    SeakeepingInput,
    evaluate_seakeeping,
    to_answer_dict,
)

SYSTEM_PROMPT = """You are a naval architecture seakeeping engineer.
Given hull particulars and sea state, compute spectral response statistics.
Respond with ONLY a JSON object (no markdown fences):
{
  "significant_heave_m": <float>,
  "mean_zero_crossing_period_s": <float>,
  "peak_rao": <float>,
  "peak_omega_rad_s": <float>,
  "m0_response": <float>,
  "max_heave_m": <float>,
  "max_roll_deg": <float>,
  "operability_pass": <bool>,
  "flags": ["small_angle_regime", ...]
}"""


@dataclass
class AuditResult:
    id: str
    model: str
    oracle_operability: bool
    model_operability: bool | None
    sig_heave_error: float | None
    peak_rao_error: float | None
    operability_match: bool
    failure_modes: list[str] = field(default_factory=list)
    raw_response: str = ""
    latency_s: float = 0.0


def oracle_from_record(record: dict) -> dict:
    inp = record["input"]
    limits = inp.get("limits", {})
    spec = SeakeepingInput(
        L=inp["L"], B=inp["B"], T=inp["T"],
        sea=SeaState(Hs_m=inp["Hs_m"], Tz_s=inp["Tz_s"]),
        heave=HeaveCoeffs(
            M_kg=1025.0 * inp["L"] * inp["B"] * inp["T"],
            A_33=0.2 * 1025.0 * inp["L"] * inp["B"] * inp["T"],
            B_33=5.0e5,
            C_33=1025.0 * 9.80665 * inp["L"] * inp["B"],
            F_mag=1025.0 * 9.80665 * inp["L"] * inp["B"],
        ),
        limits=OperabilityLimits(
            max_heave_m=limits.get("max_heave_m", 2.0),
            max_roll_deg=limits.get("max_roll_deg", 15.0),
        ),
    )
    return to_answer_dict(evaluate_seakeeping(spec))


def extract_json(text: str) -> dict | None:
    text = text.strip()
    text = re.sub(r"^```(?:json)?\s*", "", text)
    text = re.sub(r"\s*```$", "", text)
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


def classify_failures(oracle: dict, predicted: dict | None) -> list[str]:
    modes: list[str] = []
    if predicted is None:
        return ["json_parse_failure"]

    for key, rtol in (("significant_heave_m", 0.1), ("peak_rao", 0.15), ("m0_response", 0.1)):
        if key in predicted and key in oracle:
            rel = abs(predicted[key] - oracle[key]) / max(abs(oracle[key]), 1e-9)
            if rel > rtol:
                modes.append("numerical_drift")

    if predicted.get("operability_pass") != oracle.get("operability_pass"):
        modes.append("operability_mismatch")

    if oracle.get("operability_pass") is False and predicted.get("operability_pass") is True:
        modes.append("false_operability_pass")

    if not predicted.get("flags"):
        modes.append("no_validity_flags")

    return list(dict.fromkeys(modes))


def naive_baseline(record: dict) -> dict:
    """Simulates: uses Hs as significant heave, ignores spectrum integration."""
    inp = record["input"]
    Hs = inp["Hs_m"]
    return {
        "significant_heave_m": Hs,
        "mean_zero_crossing_period_s": inp["Tz_s"],
        "peak_rao": 1.0,
        "peak_omega_rad_s": 1.0,
        "m0_response": (Hs / 4.0) ** 2,
        "max_heave_m": Hs,
        "max_roll_deg": 0.0,
        "operability_pass": Hs <= inp.get("limits", {}).get("max_heave_m", 2.0),
        "flags": ["small_angle_regime"],
    }


def call_ollama(model: str, prompt: str, host: str = "http://localhost:11434") -> str:
    payload = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        "stream": False,
        "options": {"temperature": 0.1},
    }).encode()
    req = urllib.request.Request(
        f"{host}/api/chat",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read())
    return data.get("message", {}).get("content", "")


def audit_record(record: dict, model: str, *, use_baseline: str | None = None) -> AuditResult:
    oracle = oracle_from_record(record)
    t0 = time.time()

    if use_baseline == "naive":
        predicted = naive_baseline(record)
        raw = json.dumps(predicted)
    else:
        raw = call_ollama(model, record["instruction"])
        predicted = extract_json(raw)

    latency = time.time() - t0
    failures = classify_failures(oracle, predicted)

    sig_err = None
    rao_err = None
    model_op = None
    if predicted:
        if "significant_heave_m" in predicted:
            sig_err = abs(predicted["significant_heave_m"] - oracle["significant_heave_m"])
        if "peak_rao" in predicted:
            rao_err = abs(predicted["peak_rao"] - oracle["peak_rao"])
        model_op = predicted.get("operability_pass")

    return AuditResult(
        id=record["id"],
        model=model if not use_baseline else f"baseline:{use_baseline}",
        oracle_operability=oracle["operability_pass"],
        model_operability=model_op,
        sig_heave_error=sig_err,
        peak_rao_error=rao_err,
        operability_match=model_op == oracle["operability_pass"] if model_op is not None else False,
        failure_modes=failures,
        raw_response=raw[:500],
        latency_s=latency,
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="Seakeeping gap audit")
    ap.add_argument("--dataset", type=Path, required=True)
    ap.add_argument("--model", default="qwen2.5-coder:1.5b")
    ap.add_argument("--baseline", choices=["naive"])
    ap.add_argument("--n", type=int, default=0, help="Limit records (0 = all)")
    ap.add_argument("--output", type=Path, default=Path("out/seakeeping_gap_report.jsonl"))
    args = ap.parse_args()

    records = [json.loads(line) for line in args.dataset.read_text().splitlines() if line.strip()]
    if args.n > 0:
        records = records[: args.n]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    results: list[AuditResult] = []

    with args.output.open("w") as f:
        for rec in records:
            try:
                r = audit_record(rec, args.model, use_baseline=args.baseline)
            except (urllib.error.URLError, TimeoutError) as e:
                r = AuditResult(
                    id=rec["id"], model=args.model,
                    oracle_operability=False, model_operability=None,
                    sig_heave_error=None, peak_rao_error=None,
                    operability_match=False,
                    failure_modes=[f"api_error:{e}"],
                )
            results.append(r)
            f.write(json.dumps(asdict(r)) + "\n")

    n = len(results)
    op_match = sum(1 for r in results if r.operability_match)
    sig_within = sum(
        1 for r in results
        if r.sig_heave_error is not None and r.sig_heave_error < 0.5
    )
    print(f"Records: {n}")
    print(f"Operability match: {op_match}/{n} ({100*op_match/n:.1f}%)")
    print(f"Sig heave within 0.5m: {sig_within}/{n} ({100*sig_within/n:.1f}%)")
    print(f"Report: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())