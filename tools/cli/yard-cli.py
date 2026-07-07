#!/usr/bin/env python3
"""
yard-cli — thin Python facade over oracle + composition workflows.

Naval architects live in Python/MATLAB; this is the adoption bridge.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "oracle"))
sys.path.insert(0, str(Path(__file__).parent.parent / "viz"))

from render_gz_svg import render_gz_svg, render_record  # noqa: E402
from yard_stability_oracle import (  # noqa: E402
    Tank,
    WorkflowInput,
    evaluate_box_barge_workflow,
    to_answer_dict,
)


def cmd_stability(args: argparse.Namespace) -> int:
    tanks = []
    if args.tank:
        for spec in args.tank:
            l, b, rho = spec.split(",")
            tanks.append(Tank(l_m=float(l), b_m=float(b), rho_fluid=float(rho)))

    wf = evaluate_box_barge_workflow(
        WorkflowInput(
            L=args.L,
            B=args.B,
            T=args.T,
            kg_m=args.kg,
            tanks=tanks,
        )
    )
    answer = to_answer_dict(wf)
    out = {
        "input": {"L": args.L, "B": args.B, "T": args.T, "kg_m": args.kg,
                  "tanks": [{"l_m": t.l_m, "b_m": t.b_m, "rho_fluid": t.rho_fluid} for t in tanks]},
        "answer": answer,
        "gz_curve": wf.gz_curve,
        "gm0_m": wf.gm0_m,
        "gm_corrected_m": wf.gm_corrected_m,
        "overall": answer["overall"],
        "verification": {"source": "yard-stability-oracle-v0.1", "tolerance": 1e-6},
    }

    if args.json:
        print(json.dumps(out, indent=2 if args.pretty else None))
    else:
        print(f"GM₀={answer['GM0']:.4f} m  GM_corr={answer['GM_corrected']:.4f} m")
        print(f"IS Code overall: {answer['overall']}")
        for k, v in answer["imo_criteria"].items():
            print(f"  {k}: {v}")
        print(f"Flags: {', '.join(answer['flags'])}")

    if args.render:
        svg = render_gz_svg(
            wf.gz_curve,
            gm0_m=wf.gm0_m,
            gm_corrected_m=wf.gm_corrected_m,
            overall_pass=answer["overall"] == "PASS",
        )
        Path(args.render).write_text(svg, encoding="utf-8")
        print(f"SVG: {args.render}", file=sys.stderr)

    return 0


def cmd_render(args: argparse.Namespace) -> int:
    record = json.loads(Path(args.input).read_text())
    out = render_record(record, Path(args.output))
    print(f"wrote {out}")
    return 0


def cmd_eval(args: argparse.Namespace) -> int:
    sys.path.insert(0, str(Path(__file__).parent.parent / "eval"))
    from harness import main as harness_main  # noqa: E402

    sys.argv = [
        "harness.py",
        "--dataset", args.dataset,
        "--predictions", args.predictions,
        "--mode", args.mode,
    ]
    harness_main()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="yard-cli", description="Yard naval engineering CLI")
    sub = parser.add_subparsers(dest="command", required=True)

    p_stab = sub.add_parser("stability", help="Box-barge intact stability + IS Code 2.2")
    p_stab.add_argument("--L", type=float, required=True)
    p_stab.add_argument("--B", type=float, required=True)
    p_stab.add_argument("--T", type=float, required=True)
    p_stab.add_argument("--kg", type=float, required=True, help="KG above keel [m]")
    p_stab.add_argument("--tank", action="append", help="Tank spec: l,b,rho (repeatable)")
    p_stab.add_argument("--json", action="store_true")
    p_stab.add_argument("--pretty", action="store_true")
    p_stab.add_argument("--render", metavar="PATH", help="Also write GZ curve SVG")
    p_stab.set_defaults(func=cmd_stability)

    p_render = sub.add_parser("render", help="Render GZ SVG from dataset record JSON")
    p_render.add_argument("--input", required=True)
    p_render.add_argument("--output", required=True)
    p_render.set_defaults(func=cmd_render)

    p_eval = sub.add_parser("eval", help="Run eval harness")
    p_eval.add_argument("--dataset", required=True)
    p_eval.add_argument("--predictions", required=True)
    p_eval.add_argument("--mode", default="model", choices=["oracle", "model"])
    p_eval.set_defaults(func=cmd_eval)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())