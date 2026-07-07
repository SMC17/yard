#!/usr/bin/env python3
"""
Agent orchestration sketch — decompose query → yard modules → structured report + viz.

Phase 1: deterministic pipeline (no LLM). Phase 2+: fine-tuned model proposes
module calls; oracle verifies every numeric output.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent.parent / "oracle"))
sys.path.insert(0, str(Path(__file__).parent.parent / "viz"))

from render_gz_svg import render_gz_svg  # noqa: E402
from yard_stability_oracle import Tank, WorkflowInput, evaluate_box_barge_workflow, to_answer_dict  # noqa: E402


@dataclass
class ModuleCall:
    module: str
    inputs: dict[str, Any]
    outputs: dict[str, Any] = field(default_factory=dict)
    proof_level: str = "unit_tested"
    flags: list[str] = field(default_factory=list)


@dataclass
class AssessmentReport:
    query: str
    calls: list[ModuleCall]
    overall_confidence: str
    uncertainty_notes: list[str]
    assets: dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "query": self.query,
            "calls": [
                {
                    "module": c.module,
                    "inputs": c.inputs,
                    "outputs": c.outputs,
                    "proof_level": c.proof_level,
                    "flags": c.flags,
                }
                for c in self.calls
            ],
            "overall_confidence": self.overall_confidence,
            "uncertainty_notes": self.uncertainty_notes,
            "assets": self.assets,
        }


def run_stability_assessment(spec: dict, assets_dir: Path) -> AssessmentReport:
    """Deterministic orchestration: stability workflow only (Phase 1)."""
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
    answer = to_answer_dict(wf)

    uncertainty: list[str] = []
    if not wf.wall_sided_valid:
        uncertainty.append("Wall-sided assumption invalid — GZ curve may underestimate at large angles")
    if wf.gm_corrected_m < 0.15:
        uncertainty.append("GM_corrected below IS Code minimum — marginal stability regime")
    if spec["B"] / (2 * spec["T"]) < 1.2:
        uncertainty.append("B/(2T) near validity boundary for wall-sided formula")

    assets_dir.mkdir(parents=True, exist_ok=True)
    svg_path = assets_dir / "gz_curve.svg"
    svg = render_gz_svg(
        wf.gz_curve,
        gm0_m=wf.gm0_m,
        gm_corrected_m=wf.gm_corrected_m,
        overall_pass=answer["overall"] == "PASS",
    )
    svg_path.write_text(svg, encoding="utf-8")

    call = ModuleCall(
        module="yard-stability/box_barge",
        inputs=spec,
        outputs=answer,
        flags=answer["flags"],
    )

    confidence = "high" if answer["overall"] == "PASS" and not uncertainty else "medium"
    if answer["overall"] == "FAIL":
        confidence = "high"  # we are confident it fails

    return AssessmentReport(
        query=spec.get("query", "intact stability assessment"),
        calls=[call],
        overall_confidence=confidence,
        uncertainty_notes=uncertainty,
        assets={"gz_curve_svg": str(svg_path)},
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="Yard agent orchestration (Phase 1)")
    ap.add_argument("--spec", required=True, help="JSON spec file")
    ap.add_argument("--output", default="-", help="Report JSON path (- for stdout)")
    ap.add_argument("--assets-dir", default="out/agent_assets")
    args = ap.parse_args()

    spec = json.loads(Path(args.spec).read_text())
    report = run_stability_assessment(spec, Path(args.assets_dir))
    text = json.dumps(report.to_dict(), indent=2)

    if args.output == "-":
        print(text)
    else:
        Path(args.output).write_text(text, encoding="utf-8")
        print(f"report: {args.output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())