#!/usr/bin/env python3
"""
Extend text SFT records with deterministic GZ curve SVG assets.

Output: train_multimodal.jsonl with image_path + scene_graph fields.
The dataset is the deliverable — images are oracle-verified render targets.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "viz"))
from render_gz_svg import render_record  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser(description="Render multimodal stability dataset")
    ap.add_argument("--input", required=True, help="Input JSONL (train.jsonl)")
    ap.add_argument("--output", required=True, help="Output multimodal JSONL")
    ap.add_argument("--images-dir", default="out/images", help="SVG output directory")
    ap.add_argument("--max", type=int, default=0, help="Max records (0=all)")
    ap.add_argument("--format", choices=["svg"], default="svg")
    args = ap.parse_args()

    images_dir = Path(args.images_dir)
    images_dir.mkdir(parents=True, exist_ok=True)

    count = 0
    with open(args.input) as fin, open(args.output, "w") as fout:
        for line in fin:
            if args.max and count >= args.max:
                break
            record = json.loads(line)
            rid = record.get("id", f"rec-{count:06d}")
            img_path = images_dir / f"{rid}.svg"
            render_record(record, img_path)

            mm = dict(record)
            mm["assets"] = {
                "gz_curve_svg": str(img_path.relative_to(Path(args.output).parent)),
                "format": args.format,
                "renderer": "yard-viz-v0.1",
            }
            mm["scene_graph"] = {
                "type": "stability_assessment",
                "hull_form": "box_barge",
                "curves": ["gz_wall_sided"],
                "criteria": "imo_is_code_2008_part_a_2_2",
                "overall": record["answer"]["overall"],
            }
            fout.write(json.dumps(mm, separators=(",", ":")) + "\n")
            count += 1

    print(f"rendered {count} records → {args.output}")


if __name__ == "__main__":
    main()