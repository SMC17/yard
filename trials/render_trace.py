#!/usr/bin/env python3
"""Render an agent-loop trace (JSONL) as a self-contained SVG: best primary
objective vs oracle calls — the sample-efficiency curve that IS the agent
benchmark result. Usage: render_trace.py trace.jsonl out.svg"""
import json, sys

trace = [e for l in open(sys.argv[1]) if l.strip() for e in [json.loads(l)] if "call" in e]
best, xs, ys = None, [], []
for t in trace:
    if t["scored"] and t["objectives"]:
        v = t["objectives"][0]
        best = v if best is None else min(best, v)
    if best is not None:
        xs.append(t["call"]); ys.append(best)
W, H, PL, PB = 560, 320, 56, 40
lo, hi = min(ys), max(ys)
pad = (hi - lo) * 0.15 or 1
lo, hi = lo - pad, hi + pad
def sx(c): return PL + (c - xs[0]) / max(xs[-1] - xs[0], 1) * (W - PL - 16)
def sy(v): return 16 + (hi - v) / (hi - lo) * (H - PB - 16)
pts = " ".join(f"{sx(c):.1f},{sy(v):.1f}" for c, v in zip(xs, ys))
marks = "".join(
    f'<circle cx="{sx(t["call"]):.1f}" cy="{H-PB+10}" r="3" fill="#e34948"><title>call {t["call"]}: gate-rejected</title></circle>'
    for t in trace if not t["scored"])
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" font-family="system-ui" font-size="11">
<rect width="{W}" height="{H}" fill="#fcfcfb"/>
<text x="{PL}" y="12" fill="#0b0b0b" font-size="13">Agent sample efficiency — best objective vs oracle calls</text>
<polyline points="{pts}" fill="none" stroke="#2a78d6" stroke-width="2"/>
{"".join(f'<text x="{sx(c):.0f}" y="{H-PB+24}" text-anchor="middle" fill="#52514e">{c}</text>' for c in xs[::max(1,len(xs)//6)])}
<text x="8" y="{sy(ys[0]):.0f}" fill="#52514e">{ys[0]:.1f}</text>
<text x="8" y="{sy(ys[-1]):.0f}" fill="#52514e">{ys[-1]:.1f}</text>
{marks}
<text x="{PL}" y="{H-6}" fill="#52514e">red dots: gate rejections (physics said no)</text></svg>'''
open(sys.argv[2], "w").write(svg)
print(sys.argv[2], f"best {ys[-1]:.2f} after {xs[-1]} calls")
