#!/usr/bin/env python3
"""Seed-sweep campaign with bootstrap confidence intervals.

Point estimates hide seed luck. This sweeps K seeds through the (seed-
overridable) sail evaluator for every submission, then reports per-objective
mean and a bootstrap 95% CI over the seed distribution. A submission whose
CI excludes another's mean is a real difference; overlapping CIs are noise.

Usage:
  python3 trials/campaign.py [--seeds 50] [--mission-family sailmission]
  # writes trials/site/campaign-<mission>.html + campaign JSON per mission
"""

from __future__ import annotations

import argparse
import html
import json
import random
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def run_eval(binary: Path, mission: Path, sub: Path, seed: int) -> dict | None:
    proc = subprocess.run(
        [str(binary), "eval", str(mission), str(sub), "--base-seed", str(seed)],
        capture_output=True,
        text=True,
    )
    if proc.returncode not in (0, 2):
        raise RuntimeError(proc.stderr)
    r = json.loads(proc.stdout)
    return r if r["scored"] else None


def bootstrap_ci(xs: list[float], iters: int = 2000, alpha: float = 0.05, seed: int = 7) -> tuple[float, float]:
    rng = random.Random(seed)
    means = sorted(
        sum(rng.choices(xs, k=len(xs))) / len(xs) for _ in range(iters)
    )
    lo = means[int(alpha / 2 * iters)]
    hi = means[int((1 - alpha / 2) * iters) - 1]
    return lo, hi


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=50)
    args = ap.parse_args()

    module = ROOT / "sailmission"
    subprocess.run(["zig", "build", "-Doptimize=ReleaseFast"], cwd=module, check=True)
    binary = module / "zig-out" / "bin" / "yard-sail-mission"

    for mission_dir in sorted((module / "missions").iterdir()):
        mf = mission_dir / "mission.json"
        if not mf.exists():
            continue
        mission = json.loads(mf.read_text())
        obj_ids = [o["id"] for o in mission["objectives"]]
        base = mission["monte_carlo"]["base_seed"]
        seeds = [base + 1000 * i for i in range(args.seeds)]

        stats = {}
        for sub in sorted((mission_dir / "submissions").glob("*.json")):
            per_obj: list[list[float]] = [[] for _ in obj_ids]
            gated = False
            for seed in seeds:
                r = run_eval(binary, mf, sub, seed)
                if r is None:
                    gated = True
                    break
                for i, o in enumerate(r["objectives"]):
                    per_obj[i].append(o["value"])
            if gated:
                continue
            stats[json.loads(sub.read_text())["id"]] = [
                {
                    "objective": oid,
                    "mean": sum(xs) / len(xs),
                    "ci95": bootstrap_ci(xs),
                    "min": min(xs),
                    "max": max(xs),
                }
                for oid, xs in zip(obj_ids, per_obj)
            ]

        out_json = ROOT / "trials" / "results" / f"campaign-{mission['id']}.json"
        out_json.write_text(json.dumps(
            {"mission": mission["id"], "n_seeds": args.seeds, "stats": stats}, indent=1))

        rows = []
        for sid, objs in sorted(stats.items(), key=lambda kv: kv[1][0]["mean"]):
            cells = "".join(
                f"<td>{o['mean']:.2f} <span class='ci'>[{o['ci95'][0]:.2f}, {o['ci95'][1]:.2f}]</span></td>"
                for o in objs
            )
            rows.append(f"<tr><td>{html.escape(sid)}</td>{cells}</tr>")
        header = "".join(f"<th>{html.escape(o)} (mean [95% CI])</th>" for o in obj_ids)
        page = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Yard Trials — {html.escape(mission['id'])} campaign</title><style>
:root {{ --page:#f9f9f7; --ink:#0b0b0b; --ink2:#52514e; --grid:#e4e3df; }}
@media (prefers-color-scheme: dark){{ :root{{ --page:#0d0d0d; --ink:#fff; --ink2:#c3c2b7; --grid:#33332f; }} }}
body{{background:var(--page);color:var(--ink);font:15px/1.6 system-ui,sans-serif;max-width:760px;margin:2rem auto;padding:0 1rem}}
table{{border-collapse:collapse;width:100%}} th,td{{text-align:left;padding:.35rem .6rem;border-bottom:1px solid var(--grid);font-variant-numeric:tabular-nums}}
.sub,.ci{{color:var(--ink2)}} .ci{{font-size:.85em}}
</style></head><body>
<h1>{html.escape(mission['id'])} — seed campaign</h1>
<p class="sub">{args.seeds} seeds per submission, bootstrap 95% CIs over the seed
distribution (2000 resamples). Point leaderboards can hide seed luck; overlapping
CIs are noise, separated CIs are physics.</p>
<table><thead><tr><th>submission</th>{header}</tr></thead><tbody>{''.join(rows)}</tbody></table>
</body></html>"""
        (ROOT / "trials" / "site" / f"campaign-{mission['id']}.html").write_text(page)
        print(f"{mission['id']}: {len(stats)} submissions x {args.seeds} seeds")
        for sid, objs in stats.items():
            o = objs[0]
            print(f"  {sid}: {o['objective']} {o['mean']:.2f} [{o['ci95'][0]:.2f}, {o['ci95'][1]:.2f}] range [{o['min']:.1f}, {o['max']:.1f}]")
    return 0


if __name__ == "__main__":
    main()
