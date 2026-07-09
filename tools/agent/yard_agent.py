#!/usr/bin/env python3
"""
Yard Agent CLI — unified Physical AI entry point.

Subcommands:
  assess   NL/spec → oracle → compliance packet
  eval     Benchmark extraction modes on held-out eval
  demo     Quick smoke demo

Usage:
  python yard_agent.py assess --instruction "Box barge 10x4x1.5m..." --output out/packet
  python yard_agent.py eval --dataset tools/dataset/out/eval.jsonl --limit 30
  python yard_agent.py demo
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
AGENT = Path(__file__).resolve().parent


def cmd_assess(args: argparse.Namespace) -> int:
    from export_compliance_packet import build_artifact_from_instruction, write_packet
    from oracle_agent import load_record, run_oracle_agent
    from extract_spec import extract_spec

    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)

    if args.spec:
        spec = json.loads(Path(args.spec).read_text())
        query = spec.get("query", "stability assessment")
        art = run_oracle_agent(
            query=query, spec=spec, extraction_mode="spec_file", assets_dir=out,
        )
    elif args.record and args.case_id:
        rec = load_record(Path(args.record), args.case_id)
        query = rec["instruction"]
        if args.use_record_input:
            spec = rec["input"]
            mode = "record_input"
            notes: list[str] = []
        else:
            spec, notes, mode = extract_spec(
                query, mode=args.extract,  # type: ignore[arg-type]
                model=args.ollama_model, host=args.ollama_host,
            )
        art = run_oracle_agent(
            query=query, spec=spec, extraction_mode=mode,
            extraction_notes=notes, assets_dir=out,
        )
    elif args.instruction:
        art = build_artifact_from_instruction(
            args.instruction,
            extract=args.extract,
            ollama_model=args.ollama_model,
            ollama_host=args.ollama_host,
            assets_dir=out,
        )
    else:
        print("assess: provide --instruction, --spec, or --record with --id", file=sys.stderr)
        return 2

    write_packet(out, art)
    ans = art.answer
    print(f"packet: {out.resolve()}")
    print(f"overall: {ans['overall']}  GM_corr: {ans['GM_corrected']:.4f} m")
    print(f"audit: {art.audit.oracle_id} in={art.audit.input_hash} out={art.audit.output_hash}")
    return 0


def cmd_eval(args: argparse.Namespace) -> int:
    script = AGENT / "eval_oracle_agent.py"
    cmd = [
        sys.executable, str(script),
        "--dataset", str(args.dataset),
        "--ollama-model", args.ollama_model,
        "--ollama-host", args.ollama_host,
        "--modes", *args.modes,
    ]
    if args.limit:
        cmd.extend(["--limit", str(args.limit)])
    if args.output:
        cmd.extend(["--output", str(args.output)])
    return subprocess.call(cmd)


def cmd_demo(_: argparse.Namespace) -> int:
    eval_path = ROOT / "tools/dataset/out/eval.jsonl"
    case_id = json.loads(eval_path.read_text().splitlines()[0])["id"]
    out = ROOT / "tools/gap_audit/out/yard_agent_demo"
    return cmd_assess(argparse.Namespace(
        instruction=None,
        spec=None,
        record=str(eval_path),
        case_id=case_id,
        use_record_input=False,
        extract="hybrid",
        ollama_model="qwen2.5-coder:1.5b",
        ollama_host="http://127.0.0.1:11434",
        output=str(out),
    ))


def main() -> int:
    ap = argparse.ArgumentParser(prog="yard-agent", description="Yard Physical AI agent")
    sub = ap.add_subparsers(dest="command", required=True)

    p_assess = sub.add_parser("assess", help="Run stability assessment → compliance packet")
    p_assess.add_argument("--instruction")
    p_assess.add_argument("--spec", type=Path)
    p_assess.add_argument("--record", type=Path)
    p_assess.add_argument("--id", dest="case_id")
    p_assess.add_argument("--use-record-input", action="store_true")
    p_assess.add_argument("--extract", default="hybrid", choices=("regex", "ollama", "hybrid"))
    p_assess.add_argument("--ollama-model", default="qwen2.5-coder:1.5b")
    p_assess.add_argument("--ollama-host", default="http://127.0.0.1:11434")
    p_assess.add_argument("--output", required=True)
    p_assess.set_defaults(func=cmd_assess)

    p_eval = sub.add_parser("eval", help="Benchmark oracle agent on eval set")
    p_eval.add_argument("--dataset", type=Path, default=ROOT / "tools/dataset/out/eval.jsonl")
    p_eval.add_argument("--limit", type=int, default=None)
    p_eval.add_argument("--modes", nargs="+", default=["hybrid", "ollama", "record_input"])
    p_eval.add_argument("--ollama-model", default="qwen2.5-coder:1.5b")
    p_eval.add_argument("--ollama-host", default="http://127.0.0.1:11434")
    p_eval.add_argument("--output", type=Path, default=None)
    p_eval.set_defaults(func=cmd_eval)

    p_demo = sub.add_parser("demo", help="Quick demo on first eval case")
    p_demo.set_defaults(func=cmd_demo)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())