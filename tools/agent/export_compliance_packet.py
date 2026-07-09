#!/usr/bin/env python3
"""
Export a class-checkable compliance packet from a ComplianceArtifact.

Writes:
  packet/artifact.json      — full audit artifact
  packet/spec.json          — extracted problem spec
  packet/answer.json        — oracle-verified results
  packet/gz_curve.svg       — GZ curve visualization
  packet/criteria_table.md  — human-readable IS Code table
  packet/README.md          — packet index + reproduction notes

Usage:
  python export_compliance_packet.py --artifact out/artifact.json --output out/packet
  python export_compliance_packet.py --instruction "..." --output out/packet
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent))
from extract_spec import extract_spec  # noqa: E402
from oracle_agent import ComplianceArtifact, run_oracle_agent  # noqa: E402

CRITERIA_LABELS = {
    "area_0_30": "Area 0–30° ≥ 0.055 m·rad",
    "area_0_40": "Area 0–40° ≥ 0.090 m·rad",
    "area_30_40": "Area 30–40° ≥ 0.030 m·rad",
    "gz_at_30": "GZ at 30° ≥ 0.200 m",
    "angle_gz_max": "Angle of max GZ ≥ 25°",
    "gm_0": "GM₀ ≥ 0.150 m",
}


def render_criteria_md(answer: dict[str, Any], audit: dict[str, Any]) -> str:
    lines = [
        "# IMO IS Code 2008 Part A 2.2 — Criteria",
        "",
        f"**Overall:** {answer.get('overall', 'N/A')}",
        "",
        "| Criterion | Result |",
        "|-----------|--------|",
    ]
    criteria = answer.get("imo_criteria", {})
    for key, label in CRITERIA_LABELS.items():
        verdict = criteria.get(key, "—")
        lines.append(f"| {label} | **{verdict}** |")

    lines.extend([
        "",
        "## Numerics (oracle-verified)",
        "",
        f"| Quantity | Value |",
        f"|----------|-------|",
        f"| GM₀ | {answer.get('GM0', '—')} m |",
        f"| GG′ | {answer.get('GG_prime', '—')} m |",
        f"| GM corrected | {answer.get('GM_corrected', '—')} m |",
        f"| GZ at 30° | {answer.get('GZ_at_30', '—')} m |",
        "",
        "## Assumption flags",
        "",
    ])
    for flag in answer.get("flags", []):
        lines.append(f"- `{flag}`")

    lines.extend([
        "",
        "## Audit trail",
        "",
        f"- Oracle: `{audit.get('oracle_id', 'unknown')}`",
        f"- Proof level: `{audit.get('proof_level', 'unknown')}`",
        f"- Extraction: `{audit.get('extraction_mode', 'unknown')}`",
        f"- Input hash: `{audit.get('input_hash', '')}`",
        f"- Output hash: `{audit.get('output_hash', '')}`",
    ])
    return "\n".join(lines) + "\n"


def render_packet_readme(out_dir: Path, artifact: dict[str, Any]) -> str:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    audit = artifact.get("audit", {})
    return f"""# Yard Stability Compliance Packet

Generated: {ts}

## Contents

| File | Description |
|------|-------------|
| `artifact.json` | Full artifact with query, spec, answer, audit |
| `spec.json` | Extracted problem parameters |
| `answer.json` | Oracle-verified stability results |
| `gz_curve.svg` | Wall-sided GZ curve |
| `criteria_table.md` | IS Code criteria table |

## Query

{artifact.get('query', '(none)')}

## Result

**Overall:** {artifact.get('answer', {}).get('overall', 'N/A')}

## Reproduce

```sh
python tools/agent/yard_agent.py assess \\
  --instruction "<your query>" \\
  --output {out_dir}
```

Proof: `{audit.get('oracle_id')}` | Input `{audit.get('input_hash')}` | Output `{audit.get('output_hash')}`
"""


def write_packet(out_dir: Path, artifact: ComplianceArtifact | dict[str, Any]) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    if isinstance(artifact, ComplianceArtifact):
        data = artifact.to_dict()
    else:
        data = artifact

    (out_dir / "artifact.json").write_text(json.dumps(data, indent=2), encoding="utf-8")
    (out_dir / "spec.json").write_text(json.dumps(data["spec"], indent=2), encoding="utf-8")
    (out_dir / "answer.json").write_text(json.dumps(data["answer"], indent=2), encoding="utf-8")
    (out_dir / "criteria_table.md").write_text(
        render_criteria_md(data["answer"], data["audit"]), encoding="utf-8",
    )

    svg_src = data.get("assets", {}).get("gz_curve_svg")
    dst_svg = out_dir / "gz_curve.svg"
    if svg_src and Path(svg_src).exists():
        src = Path(svg_src).resolve()
        if src != dst_svg.resolve():
            shutil.copy2(src, dst_svg)
    elif not dst_svg.exists():
        (out_dir / "gz_curve.svg").write_text(
            "<!-- GZ SVG not generated; re-run with --assets-dir -->\n", encoding="utf-8",
        )

    (out_dir / "README.md").write_text(render_packet_readme(out_dir, data), encoding="utf-8")
    return out_dir


def build_artifact_from_instruction(
    instruction: str,
    *,
    extract: str = "hybrid",
    ollama_model: str = "qwen2.5-coder:1.5b",
    ollama_host: str = "http://127.0.0.1:11434",
    assets_dir: Path,
) -> ComplianceArtifact:
    spec, notes, mode = extract_spec(
        instruction, mode=extract,  # type: ignore[arg-type]
        model=ollama_model, host=ollama_host,
    )
    return run_oracle_agent(
        query=instruction,
        spec=spec,
        extraction_mode=mode,
        extraction_notes=notes,
        assets_dir=assets_dir,
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="Export stability compliance packet")
    ap.add_argument("--artifact", type=Path, help="Existing artifact.json")
    ap.add_argument("--instruction", help="NL query (runs oracle agent)")
    ap.add_argument("--spec", type=Path, help="JSON spec file")
    ap.add_argument("--extract", default="hybrid", choices=("regex", "ollama", "hybrid"))
    ap.add_argument("--ollama-model", default="qwen2.5-coder:1.5b")
    ap.add_argument("--ollama-host", default="http://127.0.0.1:11434")
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()

    assets_dir = args.output

    if args.artifact:
        data = json.loads(args.artifact.read_text())
        write_packet(args.output, data)
    elif args.instruction:
        art = build_artifact_from_instruction(
            args.instruction,
            extract=args.extract,
            ollama_model=args.ollama_model,
            ollama_host=args.ollama_host,
            assets_dir=assets_dir,
        )
        write_packet(args.output, art)
    elif args.spec:
        spec = json.loads(args.spec.read_text())
        art = run_oracle_agent(
            query=spec.get("query", "stability assessment"),
            spec=spec,
            extraction_mode="spec_file",
            assets_dir=assets_dir,
        )
        write_packet(args.output, art)
    else:
        ap.error("provide --artifact, --instruction, or --spec")

    print(f"packet: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())