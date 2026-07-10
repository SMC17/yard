#!/usr/bin/env python3
"""Re-score every Trials submission through the deterministic yard-mission
binary and rebuild the results JSONL from scratch.

The leaderboard is never hand-edited: CI runs this script and fails the PR
if the committed results differ from server-side re-execution. Submissions
are evaluated in sorted filename order so the output is byte-stable.

Usage:
  python3 trials/score.py [--binary PATH] [--check]

  --check   exit 1 if any results file changed (CI integrity gate)
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MISSIONS_DIR = ROOT / "mission" / "missions"
RESULTS_DIR = ROOT / "trials" / "results"


def build_binary() -> Path:
    subprocess.run(
        ["zig", "build"],
        cwd=ROOT / "mission",
        check=True,
    )
    return ROOT / "mission" / "zig-out" / "bin" / "yard-mission"


def score_mission(binary: Path, mission_dir: Path) -> tuple[str, list[str], list[dict]]:
    mission_file = mission_dir / "mission.json"
    mission_id = json.loads(mission_file.read_text())["id"]
    lines: list[str] = []
    reports: list[dict] = []
    for sub in sorted((mission_dir / "submissions").glob("*.json")):
        proc = subprocess.run(
            [str(binary), "eval", str(mission_file), str(sub)],
            capture_output=True,
            text=True,
        )
        if proc.returncode not in (0, 2):
            raise RuntimeError(f"eval crashed on {sub}: {proc.stderr}")
        report = json.loads(proc.stdout)
        reports.append(report)
        if not report["scored"]:
            continue
        entry = {
            "mission": report["mission"],
            "id": report["submission"],
            "author": report["author"],
            "objectives": [o["value"] for o in report["objectives"]],
        }
        lines.append(json.dumps(entry, separators=(",", ":")))
    return mission_id, lines, reports


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--binary", type=Path, default=None)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    binary = args.binary or build_binary()
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    changed = []
    for mission_dir in sorted(MISSIONS_DIR.iterdir()):
        if not (mission_dir / "mission.json").exists():
            continue
        mission_id, lines, reports = score_mission(binary, mission_dir)
        out = RESULTS_DIR / f"{mission_id}.jsonl"
        new_text = "".join(line + "\n" for line in lines)
        old_text = out.read_text() if out.exists() else None
        if old_text != new_text:
            changed.append(out)
            if not args.check:
                out.write_text(new_text)
        n_scored = len(lines)
        n_gated = len(reports) - n_scored
        print(f"{mission_id}: {n_scored} scored, {n_gated} rejected by gates")

    if args.check and changed:
        for p in changed:
            print(f"STALE: {p} does not match re-execution", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
