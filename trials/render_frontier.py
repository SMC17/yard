#!/usr/bin/env python3
"""Render a static, self-contained Pareto frontier page per mission.

Reads mission.json (objective ids + directions) and the re-scored results
JSONL, computes non-domination over ALL objectives, and draws the first two
objectives as an SVG scatter with the full objective table below. No
dependencies, no external assets; light/dark via prefers-color-scheme.

Usage: python3 trials/render_frontier.py
"""

from __future__ import annotations

import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MISSION_DIRS = [ROOT / "mission" / "missions", ROOT / "sailmission" / "missions"]
RESULTS_DIR = ROOT / "trials" / "results"
SITE_DIR = ROOT / "trials" / "site"

W, H = 640, 420
PAD_L, PAD_R, PAD_T, PAD_B = 64, 20, 20, 48


def dominates(a: list[float], b: list[float], directions: list[str]) -> bool:
    better = False
    for av, bv, d in zip(a, b, directions):
        am, bm = (av, bv) if d == "min" else (-av, -bv)
        if am > bm:
            return False
        if am < bm:
            better = True
    return better


def scale(v, lo, hi, out_lo, out_hi):
    if hi == lo:
        return (out_lo + out_hi) / 2
    return out_lo + (v - lo) / (hi - lo) * (out_hi - out_lo)


def render(mission: dict, entries: list[dict]) -> str:
    objectives = mission["objectives"]
    directions = [o["direction"] for o in objectives]
    vectors = [e["objectives"] for e in entries]
    on_front = [
        not any(dominates(w, v, directions) for w in vectors if w is not v)
        for v in vectors
    ]

    ox, oy = objectives[0], objectives[1]
    xs = [v[0] for v in vectors] or [0.0]
    ys = [v[1] for v in vectors] or [0.0]
    x_lo, x_hi = min(xs), max(xs)
    y_lo, y_hi = min(ys), max(ys)
    x_pad = (x_hi - x_lo) * 0.12 or max(abs(x_hi), 1.0) * 0.12
    y_pad = (y_hi - y_lo) * 0.12 or max(abs(y_hi), 1.0) * 0.12
    x_lo, x_hi = x_lo - x_pad, x_hi + x_pad
    y_lo, y_hi = y_lo - y_pad, y_hi + y_pad

    marks = []
    for e, v, front in zip(entries, vectors, on_front):
        cx = scale(v[0], x_lo, x_hi, PAD_L, W - PAD_R)
        cy = scale(v[1], y_lo, y_hi, H - PAD_B, PAD_T)
        name = html.escape(e["id"])
        tip = ", ".join(
            f"{o['id']} {val:.4g}" for o, val in zip(objectives, v)
        )
        cls = "front" if front else "dominated"
        marks.append(
            f'<g class="{cls}"><circle cx="{cx:.1f}" cy="{cy:.1f}" r="5">'
            f"<title>{name}: {html.escape(tip)}</title></circle>"
            f'<text x="{cx + 9:.1f}" y="{cy + 4:.1f}">{name}</text></g>'
        )

    grid = []
    for i in range(5):
        gx = PAD_L + i * (W - PAD_L - PAD_R) / 4
        gy = PAD_T + i * (H - PAD_T - PAD_B) / 4
        xv = scale(gx, PAD_L, W - PAD_R, x_lo, x_hi)
        yv = scale(gy, PAD_T, H - PAD_B, y_hi, y_lo)
        grid.append(
            f'<line class="grid" x1="{gx:.1f}" y1="{PAD_T}" x2="{gx:.1f}" y2="{H - PAD_B}"/>'
            f'<text class="tick" x="{gx:.1f}" y="{H - PAD_B + 18}" text-anchor="middle">{xv:.3g}</text>'
            f'<line class="grid" x1="{PAD_L}" y1="{gy:.1f}" x2="{W - PAD_R}" y2="{gy:.1f}"/>'
            f'<text class="tick" x="{PAD_L - 8}" y="{gy + 4:.1f}" text-anchor="end">{yv:.3g}</text>'
        )

    header = "".join(
        f"<th>{html.escape(o['id'])} ({o['direction']})</th>" for o in objectives
    )
    rows = []
    order = sorted(range(len(entries)), key=lambda i: (not on_front[i], vectors[i][0]))
    for i in order:
        cells = "".join(f"<td>{v:.6g}</td>" for v in vectors[i])
        badge = "&#9679; front" if on_front[i] else "dominated"
        rows.append(
            f"<tr><td>{html.escape(entries[i]['id'])}</td>"
            f"<td>{html.escape(entries[i].get('author', ''))}</td>"
            f'<td class="{ "front-cell" if on_front[i] else "dom-cell" }">{badge}</td>{cells}</tr>'
        )

    n_front = sum(on_front)
    title = html.escape(mission.get("title") or mission["id"])
    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Yard Trials — {title}</title>
<style>
:root {{
  --surface: #fcfcfb; --page: #f9f9f7; --ink: #0b0b0b; --ink-2: #52514e;
  --front: #2a78d6; --grid: #e4e3df;
}}
@media (prefers-color-scheme: dark) {{
  :root {{ --surface: #1a1a19; --page: #0d0d0d; --ink: #ffffff; --ink-2: #c3c2b7;
           --front: #3987e5; --grid: #33332f; }}
}}
body {{ background: var(--page); color: var(--ink); font: 15px/1.5 system-ui, sans-serif;
       max-width: 760px; margin: 2rem auto; padding: 0 1rem; }}
h1 {{ font-size: 1.3rem; }} .sub {{ color: var(--ink-2); }}
svg {{ background: var(--surface); border-radius: 8px; width: 100%; height: auto; }}
.grid {{ stroke: var(--grid); stroke-width: 1; }}
.tick, .axis {{ fill: var(--ink-2); font-size: 11px; }}
.front circle {{ fill: var(--front); }}
.dominated circle {{ fill: none; stroke: var(--ink-2); stroke-width: 1.5; }}
g text {{ fill: var(--ink); font-size: 11px; }}
.legend {{ color: var(--ink-2); margin: .4rem 0 1.2rem; }}
.legend .dot {{ color: var(--front); }}
table {{ border-collapse: collapse; width: 100%; overflow-x: auto; display: block; }}
th, td {{ text-align: left; padding: .35rem .6rem; border-bottom: 1px solid var(--grid);
          font-variant-numeric: tabular-nums; white-space: nowrap; }}
.front-cell {{ color: var(--front); }} .dom-cell {{ color: var(--ink-2); }}
</style></head><body>
<h1>Yard Trials — {title}</h1>
<p class="sub">{len(entries)} scored entries, {n_front} on the Pareto front.
Every point re-verified by deterministic physics; gate-failed designs never appear.</p>
<svg viewBox="0 0 {W} {H}" role="img" aria-label="Pareto scatter of {html.escape(ox['id'])} vs {html.escape(oy['id'])}">
{''.join(grid)}
<text class="axis" x="{(PAD_L + W - PAD_R) / 2}" y="{H - 8}" text-anchor="middle">{html.escape(ox['id'])} ({ox['direction']})</text>
<text class="axis" x="14" y="{(PAD_T + H - PAD_B) / 2}" text-anchor="middle" transform="rotate(-90 14 {(PAD_T + H - PAD_B) / 2})">{html.escape(oy['id'])} ({oy['direction']})</text>
{''.join(marks)}
</svg>
<p class="legend"><span class="dot">&#9679;</span> Pareto front &nbsp;&nbsp; &#9675; dominated
&nbsp;&nbsp;&middot;&nbsp; scatter shows the first two objectives; the table (and front/dominated
status) uses all {len(objectives)}.</p>
<table><thead><tr><th>submission</th><th>author</th><th>status</th>{header}</tr></thead>
<tbody>{''.join(rows)}</tbody></table>
</body></html>
"""


def main() -> None:
    SITE_DIR.mkdir(parents=True, exist_ok=True)
    mission_dirs = []
    for base in MISSION_DIRS:
        if base.is_dir():
            mission_dirs.extend(sorted(base.iterdir()))
    for mission_dir in mission_dirs:
        mf = mission_dir / "mission.json"
        if not mf.exists():
            continue
        mission = json.loads(mf.read_text())
        results = RESULTS_DIR / f"{mission['id']}.jsonl"
        entries = []
        if results.exists():
            entries = [e for l in results.read_text().splitlines() if l.strip() for e in [json.loads(l)] if "objectives" in e and "id" in e]
        out = SITE_DIR / f"{mission['id']}.html"
        out.write_text(render(mission, entries))
        print(f"{out.relative_to(ROOT)}: {len(entries)} entries")


if __name__ == "__main__":
    main()
