#!/usr/bin/env python3
"""
Unified agent harness — dispatch yard compose workflows with oracle verification.

Phase 1: deterministic pipelines (no LLM). Each workflow runs the Python oracle
and optionally compares model output when --model-output is supplied.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).parent.parent / "oracle"))

from yard_seakeeping_oracle import (  # noqa: E402
    HeaveCoeffs,
    OperabilityLimits,
    SeaState,
    SeakeepingInput,
    default_barge_input,
    evaluate_seakeeping,
    to_answer_dict as seakeeping_to_answer,
)
from yard_damage_oracle import DamageInput, evaluate_damage, to_answer_dict as damage_to_answer  # noqa: E402
from yard_stability_oracle import (  # noqa: E402
    Tank,
    WorkflowInput,
    evaluate_box_barge_workflow,
    to_answer_dict as stability_to_answer,
)

WORKFLOWS = ("box_barge", "seakeeping", "damage_stability")


@dataclass
class HarnessResult:
    workflow: str
    oracle: dict[str, Any]
    model: dict[str, Any] | None = None
    verify_pass: bool = True
    verify_notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "workflow": self.workflow,
            "oracle": self.oracle,
            "model": self.model,
            "verify_pass": self.verify_pass,
            "verify_notes": self.verify_notes,
        }


def _run_box_barge(spec: dict) -> dict:
    tanks = [Tank(**t) for t in spec.get("tanks", [])]
    wf = evaluate_box_barge_workflow(
        WorkflowInput(
            L=spec["L"],
            B=spec["B"],
            T=spec["T"],
            kg_m=spec["kg_m"],
            tanks=tanks,
        )
    )
    return stability_to_answer(wf)


def _run_damage(spec: dict) -> dict:
    tanks = [Tank(**t) for t in spec.get("tanks", [])]
    out = evaluate_damage(
        DamageInput(
            L=spec["L"],
            B=spec["B"],
            T=spec["T"],
            kg_m=spec["kg_m"],
            l_lost_m=spec["l_lost_m"],
            depth_m=spec["depth_m"],
            mu=spec.get("mu", 1.0),
            tanks=tanks,
        )
    )
    return damage_to_answer(out)


def _run_seakeeping(spec: dict) -> dict:
    if all(k in spec for k in ("L", "B", "T", "Hs_m", "Tz_s")):
        inp = default_barge_input(
            L=spec["L"],
            B=spec["B"],
            T=spec["T"],
            Hs_m=spec["Hs_m"],
            Tz_s=spec["Tz_s"],
        )
    else:
        inp = default_barge_input()

    if "heave" in spec:
        h = spec["heave"]
        inp.heave = HeaveCoeffs(**h)
    if "limits" in spec:
        inp.limits = OperabilityLimits(**spec["limits"])
    if "sea" in spec:
        inp.sea = SeaState(**spec["sea"])

    out = evaluate_seakeeping(inp)
    return seakeeping_to_answer(out)


RUNNERS: dict[str, Callable[[dict], dict]] = {
    "box_barge": _run_box_barge,
    "seakeeping": _run_seakeeping,
    "damage_stability": _run_damage,
}


def _rel_close(a: float, b: float, rtol: float = 0.02, atol: float = 0.05) -> bool:
    return abs(a - b) <= max(atol, rtol * max(abs(a), abs(b), 1e-9))


def verify_against_oracle(workflow: str, oracle: dict, model: dict) -> tuple[bool, list[str]]:
    notes: list[str] = []
    ok = True

    if workflow == "box_barge":
        for key in ("gm_corrected_m", "gm0_m"):
            if key in model and key in oracle:
                if not _rel_close(float(model[key]), float(oracle[key]), rtol=0.01, atol=0.02):
                    ok = False
                    notes.append(f"{key} mismatch: model={model[key]} oracle={oracle[key]}")
        if "overall" in model and "overall" in oracle and model["overall"] != oracle["overall"]:
            ok = False
            notes.append(f"overall mismatch: model={model['overall']} oracle={oracle['overall']}")

    elif workflow == "damage_stability":
        for key in ("T_damaged_m", "GM_corrected_damaged_m"):
            if key in model and key in oracle:
                if not _rel_close(float(model[key]), float(oracle[key]), rtol=0.02, atol=0.05):
                    ok = False
                    notes.append(f"{key} mismatch: model={model[key]} oracle={oracle[key]}")
        if "overall" in model and model["overall"] != oracle.get("overall"):
            ok = False
            notes.append("overall mismatch")

    elif workflow == "seakeeping":
        for key in ("significant_heave_m", "peak_rao", "m0_response"):
            if key in model and key in oracle:
                if not _rel_close(float(model[key]), float(oracle[key]), rtol=0.05, atol=0.1):
                    ok = False
                    notes.append(f"{key} mismatch: model={model[key]} oracle={oracle[key]}")
        if "operability_pass" in model and model["operability_pass"] != oracle.get("operability_pass"):
            ok = False
            notes.append("operability_pass mismatch")

    return ok, notes


def run_harness(
    workflow: str,
    spec: dict,
    model_output: dict | None = None,
    samples: int = 1,
) -> HarnessResult:
    if workflow not in RUNNERS:
        raise ValueError(f"unknown workflow: {workflow}. Choose from {WORKFLOWS}")

    oracle = RUNNERS[workflow](spec)
    verify_pass = True
    notes: list[str] = []

    if model_output is not None:
        verify_pass, notes = verify_against_oracle(workflow, oracle, model_output)
    elif samples > 1:
        notes.append(f"oracle-only mode ({samples} samples requested; single spec run)")

    return HarnessResult(
        workflow=workflow,
        oracle=oracle,
        model=model_output,
        verify_pass=verify_pass,
        verify_notes=notes,
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="Yard unified agent harness")
    ap.add_argument("--workflow", required=True, choices=WORKFLOWS)
    ap.add_argument("--spec", help="JSON spec file (defaults per workflow)")
    ap.add_argument("--model-output", help="JSON model answer to verify")
    ap.add_argument("--samples", type=int, default=1, help="Reserved for batch runs")
    ap.add_argument("--output", default="-", help="Result JSON (- for stdout)")
    args = ap.parse_args()

    if args.spec:
        spec = json.loads(Path(args.spec).read_text())
    elif args.workflow == "box_barge":
        spec = json.loads((Path(__file__).parent.parent.parent / "examples/agent_spec.json").read_text())
    elif args.workflow == "damage_stability":
        spec = {"L": 10.0, "B": 4.0, "T": 1.5, "kg_m": 1.0, "l_lost_m": 2.0, "depth_m": 3.0}
    else:
        spec = {"L": 100.0, "B": 16.0, "T": 6.0, "Hs_m": 2.0, "Tz_s": 8.0}

    model = json.loads(Path(args.model_output).read_text()) if args.model_output else None
    result = run_harness(args.workflow, spec, model_output=model, samples=args.samples)
    text = json.dumps(result.to_dict(), indent=2)

    if args.output == "-":
        print(text)
    else:
        Path(args.output).write_text(text, encoding="utf-8")
        print(f"result: {args.output}", file=sys.stderr)
    return 0 if result.verify_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())