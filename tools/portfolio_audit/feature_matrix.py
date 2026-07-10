#!/usr/bin/env python3
"""
Map README 'What it does' bullets to src/ test evidence.

Usage:
  python feature_matrix.py [--strict] [--json]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

YARD_ROOT = Path(__file__).resolve().parents[2]

MODULES = [
    "hydro", "stability", "resistance", "csr", "stir", "cii", "benchmark", "spiral",
    "compose", "viz", "naval-arch", "seakeeping", "dynpos", "fossen-6dof",
]


def extract_bullets(readme: str) -> list[str]:
    bullets: list[str] = []
    in_section = False
    for line in readme.splitlines():
        low = line.lower()
        if "what it does" in low:
            in_section = True
            continue
        if in_section and ("what it is not" in low or line.startswith("## ")):
            break
        if in_section and line.strip().startswith("-"):
            bullets.append(line.strip().lstrip("- ").strip())
    return bullets


def keywords_from_bullet(bullet: str) -> list[str]:
    # Backtick identifiers and first word tokens.
    ids = re.findall(r"`([a-zA-Z_][a-zA-Z0-9_.]*)`", bullet)
    if ids:
        return [i.split(".")[-1].lower() for i in ids[:3]]
    words = re.findall(r"[a-zA-Z_][a-zA-Z0-9_]+", bullet)
    return [w.lower() for w in words[:2] if len(w) > 3]


def scan_tests(module: str) -> str:
    root = YARD_ROOT / module / "src"
    if not root.exists():
        return ""
    parts: list[str] = []
    for zig in root.rglob("*.zig"):
        parts.append(zig.read_text())
    return "\n".join(parts)


def audit_module(name: str) -> dict:
    readme = YARD_ROOT / name / "README.md"
    if not readme.exists():
        return {"module": name, "bullets": 0, "covered": 0, "gaps": ["no README"]}

    bullets = extract_bullets(readme.read_text())
    corpus = scan_tests(name)
    gaps: list[str] = []
    covered = 0
    for b in bullets:
        keys = keywords_from_bullet(b)
        if not keys:
            continue
        if any(k in corpus.lower() for k in keys):
            covered += 1
        else:
            gaps.append(b[:80])

    return {
        "module": name,
        "bullets": len(bullets),
        "covered": covered,
        "coverage_pct": round(100 * covered / len(bullets), 1) if bullets else 100.0,
        "gaps": gaps[:5],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--min-coverage", type=float, default=50.0)
    args = parser.parse_args()

    results = [audit_module(m) for m in MODULES]
    if args.json:
        print(json.dumps(results, indent=2))
        return 0

    failing = []
    for r in results:
        pct = r.get("coverage_pct", 0)
        status = "OK" if pct >= args.min_coverage else "LOW"
        print(f"{status} {r['module']}: {r.get('covered', 0)}/{r.get('bullets', 0)} bullets ({pct}%)")
        if status == "LOW":
            failing.append(r)

    if args.strict and failing:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())