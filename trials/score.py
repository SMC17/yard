#!/usr/bin/env python3
"""Re-score every Trials submission through the deterministic evaluators and
rebuild the results JSONL from scratch.

Handles both mission families:
  mission/missions/*      power missions  (yard-mission)
  sailmission/missions/*  sail missions   (yard-sail-mission)

The leaderboard is never hand-edited: CI runs this script and fails the PR
if the committed results differ from server-side re-execution. Submissions
are evaluated in sorted filename order so the output is byte-stable.

Usage:
  python3 trials/score.py [--check] [--holdout-seed N]

  --check           exit 1 if any results file changed (CI integrity gate)
  --holdout-seed N  re-score with an overridden seed into
                    trials/results-holdout/ (never committed) and print a
                    public-vs-holdout comparison per mission
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULTS_DIR = ROOT / "trials" / "results"
HOLDOUT_DIR = ROOT / "trials" / "results-holdout"

FAMILIES = [
    # (missions dir, module dir, binary name, supports --base-seed)
    # yard-mission gains seed override when the in-flight arena RNG work
    # lands; holdout honestly skips it until then rather than reporting a
    # fake zero drift from an ignored flag.
    (ROOT / "mission" / "missions", ROOT / "mission", "yard-mission", False),
    (ROOT / "sailmission" / "missions", ROOT / "sailmission", "yard-sail-mission", True),
]


def build_binary(module_dir: Path, name: str) -> Path:
    subprocess.run(
        ["zig", "build", "-Doptimize=ReleaseFast"],
        cwd=module_dir,
        check=True,
    )
    return module_dir / "zig-out" / "bin" / name


def score_mission(
    binary: Path, mission_dir: Path, holdout_seed: int | None
) -> tuple[str, list[str], int]:
    mission_file = mission_dir / "mission.json"
    mission_id = json.loads(mission_file.read_text())["id"]
    lines: list[str] = []
    rejected = 0
    for sub in sorted((mission_dir / "submissions").glob("*.json")):
        cmd = [str(binary), "eval", str(mission_file), str(sub)]
        if holdout_seed is not None:
            cmd += ["--base-seed", str(holdout_seed)]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode not in (0, 2):
            raise RuntimeError(f"eval crashed on {sub}: {proc.stderr}")
        report = json.loads(proc.stdout)
        if not report["scored"]:
            rejected += 1
            continue
        entry = {
            "mission": report["mission"],
            "id": report["submission"],
            "author": report["author"],
            "objectives": [o["value"] for o in report["objectives"]],
        }
        lines.append(json.dumps(entry, separators=(",", ":")))
    return mission_id, lines, rejected


def rank_map(text: str) -> dict[str, list[float]]:
    out = {}
    for line in text.splitlines():
        if line.strip():
            e = json.loads(line)
            out[e["id"]] = e["objectives"]
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--holdout-seed", type=int, default=None)
    args = ap.parse_args()

    out_dir = HOLDOUT_DIR if args.holdout_seed is not None else RESULTS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    changed = []
    for missions_dir, module_dir, bin_name, supports_seed in FAMILIES:
        if not missions_dir.is_dir():
            continue
        if args.holdout_seed is not None and not supports_seed:
            print(f"{bin_name}: skipped in holdout mode (no --base-seed support yet)")
            continue
        binary = build_binary(module_dir, bin_name)
        for mission_dir in sorted(missions_dir.iterdir()):
            if not (mission_dir / "mission.json").exists():
                continue
            mission_id, lines, rejected = score_mission(
                binary, mission_dir, args.holdout_seed
            )
            out = out_dir / f"{mission_id}.jsonl"
            new_text = "".join(line + "\n" for line in lines)
            old_text = out.read_text() if out.exists() else None
            if old_text != new_text:
                changed.append(out)
                if not args.check:
                    out.write_text(new_text)
            print(f"{mission_id}: {len(lines)} scored, {rejected} rejected by gates")

            if args.holdout_seed is not None:
                public = RESULTS_DIR / f"{mission_id}.jsonl"
                if public.exists():
                    pub = rank_map(public.read_text())
                    hold = rank_map(new_text)
                    obj_ids = [
                        o["id"]
                        for o in json.loads((mission_dir / "mission.json").read_text())["objectives"]
                    ]
                    for sid in sorted(pub):
                        if sid in hold:
                            pairs = ", ".join(
                                f"{oid} {a:.4g}->{b:.4g}"
                                for oid, a, b in zip(obj_ids, pub[sid], hold[sid])
                            )
                            print(f"  holdout {sid}: {pairs}")

    if args.check and changed:
        for p in changed:
            print(f"STALE: {p} does not match re-execution", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
