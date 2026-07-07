#!/usr/bin/env python3
"""
Deterministic GZ curve SVG renderer — mirrors viz/src/gz_svg.zig output.

Used by multimodal dataset pipeline. No matplotlib dependency.
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Sequence


def _max_gz(points: Sequence[dict]) -> float:
    m = max((p["gz_m"] for p in points), default=0.0)
    return m if m > 0.01 else 0.5


def _gz_at_30(points: Sequence[dict]) -> float:
    for p in points:
        if abs(p["angle_deg"] - 30.0) < 0.01:
            return p["gz_m"]
    return 0.0


def render_gz_svg(
    points: Sequence[dict],
    *,
    gm0_m: float,
    gm_corrected_m: float,
    overall_pass: bool,
    title: str = "GZ Curve — Box Barge (wall-sided)",
    width: int = 640,
    height: int = 400,
    margin: int = 48,
) -> str:
    if not points:
        raise ValueError("NoPoints")

    plot_w = width - 2 * margin
    plot_h = height - 2 * margin
    max_angle = 40.0
    max_gz = _max_gz(points)
    gz30 = _gz_at_30(points)
    status = "PASS" if overall_pass else "FAIL"
    status_color = "#43a047" if overall_pass else "#e53935"
    x0, y0 = margin, margin + 16

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">',
        f'  <rect width="100%" height="100%" fill="#fafafa"/>',
        f'  <text x="{margin}" y="24" font-family="monospace" font-size="14" fill="#212121">{title}</text>',
        f'  <text x="{margin}" y="40" font-family="monospace" font-size="11" fill="#616161">'
        f'GM₀={gm0_m:.3f}m  GM_corr={gm_corrected_m:.3f}m  IS Code: '
        f'<tspan fill="{status_color}">{status}</tspan></text>',
        f'  <rect x="{x0}" y="{y0}" width="{plot_w}" height="{plot_h}" fill="white" stroke="#bdbdbd"/>',
    ]

    for deg in range(0, 41, 10):
        px = x0 + int((deg / max_angle) * plot_w)
        lines.append(
            f'  <line x1="{px}" y1="{y0}" x2="{px}" y2="{y0 + plot_h}" stroke="#e0e0e0"/>'
        )
        lines.append(
            f'  <text x="{px}" y="{y0 + plot_h + 14}" font-family="monospace" '
            f'font-size="10" fill="#757575" text-anchor="middle">{deg}°</text>'
        )

    step = max_gz / 5.0
    gz_tick = 0.0
    while gz_tick <= max_gz + 1e-6:
        py = y0 + plot_h - int((gz_tick / max_gz) * plot_h)
        lines.append(
            f'  <line x1="{x0}" y1="{py}" x2="{x0 + plot_w}" y2="{py}" stroke="#e0e0e0"/>'
        )
        lines.append(
            f'  <text x="{x0 - 4}" y="{py + 4}" font-family="monospace" '
            f'font-size="10" fill="#757575" text-anchor="end">{gz_tick:.2f}</text>'
        )
        gz_tick += step

    th_gz30 = 0.200
    th_y = y0 + plot_h - int((th_gz30 / max_gz) * plot_h)
    lines.append(
        f'  <line x1="{x0}" y1="{th_y}" x2="{x0 + plot_w}" y2="{th_y}" '
        f'stroke="#e53935" stroke-width="1" stroke-dasharray="4,4"/>'
    )

    poly = []
    for p in points:
        px = x0 + int((p["angle_deg"] / max_angle) * plot_w)
        py = y0 + plot_h - int((p["gz_m"] / max_gz) * plot_h)
        poly.append(f"{px},{py}")
    lines.append(
        f'  <polyline fill="none" stroke="#1e88e5" stroke-width="2.5" points="{" ".join(poly)}"/>'
    )

    px30 = x0 + int((30.0 / max_angle) * plot_w)
    py30 = y0 + plot_h - int((gz30 / max_gz) * plot_h)
    lines.append(f'  <circle cx="{px30}" cy="{py30}" r="5" fill="#1e88e5"/>')
    lines.append(
        f'  <text x="{px30 + 8}" y="{py30 - 8}" font-family="monospace" '
        f'font-size="10" fill="#1e88e5">GZ@30°={gz30:.3f}m</text>'
    )
    lines.append(
        f'  <text x="{x0 + plot_w // 2}" y="{y0 + plot_h + 32}" font-family="monospace" '
        f'font-size="12" fill="#424242" text-anchor="middle">Heel angle φ [deg]</text>'
    )
    lines.append("</svg>")
    return "\n".join(lines)


def render_record(record: dict, output_path: Path) -> Path:
    """Render a dataset JSONL record to SVG."""
    import sys

    sys.path.insert(0, str(Path(__file__).parent.parent / "oracle"))
    from yard_stability_oracle import Tank, WorkflowInput, evaluate_box_barge_workflow  # noqa: E402

    inp = record.get("input", {})
    tanks = [Tank(**t) for t in inp.get("tanks", [])]
    wf = evaluate_box_barge_workflow(
        WorkflowInput(
            L=inp["L"],
            B=inp["B"],
            T=inp["T"],
            kg_m=inp["kg_m"],
            tanks=tanks,
        )
    )
    svg = render_gz_svg(
        wf.gz_curve,
        gm0_m=wf.gm0_m,
        gm_corrected_m=wf.gm_corrected_m,
        overall_pass=wf.is_code.overall.value == "PASS",
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(svg, encoding="utf-8")
    return output_path


if __name__ == "__main__":
    import json
    import sys

    if len(sys.argv) < 3:
        print("usage: render_gz_svg.py <record.jsonl-line-or-file> <output.svg>")
        sys.exit(1)

    src = Path(sys.argv[1])
    if src.suffix == ".jsonl":
        line = src.read_text().splitlines()[0]
        record = json.loads(line)
    else:
        record = json.loads(src.read_text())

    out = render_record(record, Path(sys.argv[2]))
    print(f"wrote {out}")