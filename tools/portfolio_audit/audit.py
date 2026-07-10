#!/usr/bin/env python3
"""Portfolio documentation completeness gate for yard modules."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

YARD_ROOT = Path(__file__).resolve().parents[2]

# build.zig all_modules + platform modules
MODULES = [
    "ais", "anchor", "auv", "azipod", "bem", "bow", "cargo", "cathodic", "cavitation",
    "cii", "collision", "combat", "coupled-motions", "csr", "csr-buckling", "csr-fatigue",
    "deck", "deicing", "drydock", "dynpos", "eedi", "engine", "flettner", "fmi", "foilcraft",
    "fossen-6dof", "fueltank", "grounding", "helideck", "hess-smith-3d", "hydro", "icebreaker",
    "irf", "ittc78", "jacket", "keel", "launch", "load-line", "maneuvering", "mass", "mooring",
    "noise", "pipeline", "port-engineering", "port-logistics", "propulsion", "rao-spectrum",
    "recycling", "resistance", "roro", "routing", "saildrone", "savitsky", "seakeeping",
    "shaft", "shipyard-mgmt", "sloshing", "springing", "stability", "stir", "strength",
    "strip-theory", "submarine", "terminal", "towing-tank", "tug", "vimstab", "windaero",
    "similarity", "benchmark", "spiral", "naval-arch", "compose", "viz",
]


def audit_module(name: str) -> dict:
    root = YARD_ROOT / name
    readme = root / "README.md"
    status = root / "STATUS.md"
    src_root = root / "src" / "root.zig"

    issues: list[str] = []
    readme_text = readme.read_text() if readme.exists() else ""

    if not readme.exists():
        issues.append("missing README.md")
    else:
        lower = readme_text.lower()
        if "what it does" not in lower and "## modules" not in lower:
            issues.append("missing ## What it does")
        if "what it is not" not in lower:
            issues.append("missing ## What it is not")

    if not status.exists():
        issues.append("missing STATUS.md")
    elif "proof-vocabulary index" not in status.read_text().lower():
        issues.append("missing proof-vocabulary index in STATUS")

    if not src_root.exists():
        issues.append("missing src/root.zig")
    elif "test" not in src_root.read_text():
        issues.append("src/root.zig has no tests")

    return {
        "module": name,
        "compliant": len(issues) == 0,
        "issues": issues,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--strict", action="store_true", help="Exit 1 if any module fails")
    args = parser.parse_args()

    results = [audit_module(m) for m in MODULES]
    compliant = [r for r in results if r["compliant"]]
    failing = [r for r in results if not r["compliant"]]

    if args.json:
        print(json.dumps({"compliant": len(compliant), "failing": len(failing), "results": results}, indent=2))
    else:
        print(f"Portfolio audit: {len(compliant)}/{len(results)} compliant")
        for r in failing:
            print(f"  FAIL {r['module']}: {', '.join(r['issues'])}")

    if args.strict and failing:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())