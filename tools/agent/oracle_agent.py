#!/usr/bin/env python3
"""
Oracle-grounded stability agent — numbers from Zig oracle, never hallucinated.

Phase 2 architecture: model (optional) proposes structure; oracle computes truth.
This module runs the deterministic path: parse/extract spec → oracle → audit artifact.

Usage:
  python oracle_agent.py --spec examples/agent_spec.json --assets-dir out/demo
  python oracle_agent.py --record tools/dataset/out/eval.jsonl --id <case_id>
  python oracle_agent.py --instruction "Box barge L=10m B=4m T=1.5m KG=1.0m ..."
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent.parent / "oracle"))
sys.path.insert(0, str(Path(__file__).parent.parent / "viz"))

from render_gz_svg import render_gz_svg  # noqa: E402
from yard_stability_oracle import (  # noqa: E402
    Tank,
    WorkflowInput,
    evaluate_box_barge_workflow,
    to_answer_dict,
)

PROOF_LEVEL = "unit_tested_analytical"
ORACLE_ID = "yard-stability-oracle-v0.1"


@dataclass
class AuditTrail:
    oracle_id: str
    proof_level: str
    input_hash: str
    output_hash: str
    extraction_mode: str
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "oracle_id": self.oracle_id,
            "proof_level": self.proof_level,
            "input_hash": self.input_hash,
            "output_hash": self.output_hash,
            "extraction_mode": self.extraction_mode,
            "notes": self.notes,
        }


@dataclass
class ComplianceArtifact:
    query: str
    spec: dict[str, Any]
    answer: dict[str, Any]
    audit: AuditTrail
    assets: dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "query": self.query,
            "spec": self.spec,
            "answer": self.answer,
            "audit": self.audit.to_dict(),
            "assets": self.assets,
        }


def _stable_hash(obj: dict) -> str:
    payload = json.dumps(obj, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()[:16]


def extract_spec_from_instruction(text: str) -> tuple[dict[str, Any], list[str]]:
    """Regex extraction from natural-language stability prompts."""
    notes: list[str] = []
    # Order matters: prefer unit-suffixed conversational forms before loose key=value.
    l_m = _first_float(text, [
        r"LPP\s*=\s*([\d.]+)",
        r"(?:^|\s)L\s*=\s*([\d.]+)\s*m",
        r"(?:^|[\s□])L\s*=\s*([\d.]+)\s*m",
        r"(\d+(?:\.\d+)?)\s*m\s+long",
        r"L\s*=\s*([\d.]+)",
    ])
    b_m = _first_float(text, [
        r"(\d+(?:\.\d+)?)\s*m\s+beam",
        r"(?:^|[\s□])B\s*=\s*([\d.]+)\s*m",
        r"B\s*=\s*([\d.]+)",
    ])
    t_m = _first_float(text, [
        r"(\d+(?:\.\d+)?)\s*m\s+draft",
        r"draft\s+T\s*=\s*([\d.]+)",
        r"(?:^|[\s□])T\s*=\s*([\d.]+)\s*m",
        r"T\s*=\s*([\d.]+)\s*m",
        r"T\s*=\s*([\d.]+)",
    ])
    kg_m = _first_float(text, [
        r"(?:^|[\s□])KG\s*=\s*([\d.]+)\s*m",
        r"KG\s*=\s*([\d.]+)\s*m",
        r"KG\s*=\s*([\d.]+)",
        r"[Cc]enter of gravity is\s+([\d.]+)\s*m",
        r"gravity\s+is\s+([\d.]+)\s*m",
    ])

    if None in (l_m, b_m, t_m, kg_m):
        raise ValueError(
            f"could not extract L/B/T/KG from instruction: "
            f"L={l_m} B={b_m} T={t_m} KG={kg_m}"
        )

    tanks: list[dict[str, float]] = []
    for m in re.finditer(
        r"Tank\s*\d*\s*:\s*([\d.]+)\s*[×x]\s*([\d.]+)\s*m(?:\s*\(([^)]+)\))?",
        text,
        re.IGNORECASE,
    ):
        rho = 1000.0
        fluid = (m.group(3) or "").lower()
        if "sea" in fluid:
            rho = 1025.0
        elif re.search(r"ρ\s*=\s*(\d+)", fluid):
            rho = float(re.search(r"ρ\s*=\s*(\d+)", fluid).group(1))
        tanks.append({"l_m": float(m.group(1)), "b_m": float(m.group(2)), "rho_fluid": rho})

    if not tanks and re.search(r"no\s+slack\s+tank", text, re.IGNORECASE):
        notes.append("explicit_no_tanks")

    spec: dict[str, Any] = {
        "L": l_m,
        "B": b_m,
        "T": t_m,
        "kg_m": kg_m,
        "tanks": tanks,
    }
    return spec, notes


def _first_float(text: str, patterns: list[str]) -> float | None:
    for pat in patterns:
        m = re.search(pat, text, re.IGNORECASE)
        if m:
            return float(m.group(1))
    return None


def run_oracle_agent(
    *,
    query: str,
    spec: dict[str, Any],
    extraction_mode: str,
    extraction_notes: list[str] | None = None,
    assets_dir: Path | None = None,
) -> ComplianceArtifact:
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

    assets: dict[str, str] = {}
    if assets_dir is not None:
        assets_dir.mkdir(parents=True, exist_ok=True)
        svg_path = assets_dir / "gz_curve.svg"
        svg_path.write_text(
            render_gz_svg(
                wf.gz_curve,
                gm0_m=wf.gm0_m,
                gm_corrected_m=wf.gm_corrected_m,
                overall_pass=answer["overall"] == "PASS",
            ),
            encoding="utf-8",
        )
        assets["gz_curve_svg"] = str(svg_path)

    audit = AuditTrail(
        oracle_id=ORACLE_ID,
        proof_level=PROOF_LEVEL,
        input_hash=_stable_hash(spec),
        output_hash=_stable_hash(answer),
        extraction_mode=extraction_mode,
        notes=list(extraction_notes or []),
    )

    return ComplianceArtifact(
        query=query,
        spec=spec,
        answer=answer,
        audit=audit,
        assets=assets,
    )


def load_record(dataset: Path, case_id: str) -> dict:
    for line in dataset.read_text().splitlines():
        if not line.strip():
            continue
        rec = json.loads(line)
        if rec["id"] == case_id:
            return rec
    raise KeyError(f"case id not found: {case_id}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Oracle-grounded stability agent")
    ap.add_argument("--spec", type=Path, help="JSON spec file")
    ap.add_argument("--instruction", help="Natural language problem statement")
    ap.add_argument("--record", type=Path, help="JSONL dataset (with --id)")
    ap.add_argument("--id", help="Case id inside --record")
    ap.add_argument("--use-record-input", action="store_true",
                    help="Use record input field (skip NL extraction)")
    ap.add_argument("--assets-dir", type=Path, default=None)
    ap.add_argument("--output", default="-")
    args = ap.parse_args()

    extraction_mode = "spec_file"
    extraction_notes: list[str] = []
    query = ""
    spec: dict[str, Any]

    if args.record and args.id:
        rec = load_record(args.record, args.id)
        query = rec["instruction"]
        if args.use_record_input:
            spec = rec["input"]
            extraction_mode = "record_input"
        else:
            spec, extraction_notes = extract_spec_from_instruction(query)
            extraction_mode = "instruction_regex"
    elif args.instruction:
        query = args.instruction
        spec, extraction_notes = extract_spec_from_instruction(query)
        extraction_mode = "instruction_regex"
    elif args.spec:
        spec = json.loads(args.spec.read_text())
        query = spec.get("query", "stability assessment")
        extraction_mode = "spec_file"
    else:
        ap.error("provide --spec, --instruction, or --record with --id")

    artifact = run_oracle_agent(
        query=query,
        spec=spec,
        extraction_mode=extraction_mode,
        extraction_notes=extraction_notes,
        assets_dir=args.assets_dir,
    )
    text = json.dumps(artifact.to_dict(), indent=2)
    if args.output == "-":
        print(text)
    else:
        Path(args.output).write_text(text, encoding="utf-8")
        print(f"artifact: {args.output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())