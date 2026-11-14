#!/usr/bin/env python3
"""Fetch public reference datasets for Yard into data/cache/ (git-ignored) and verify checksums.

Only sources whose licence does not clearly allow redistribution are fetched
here instead of being committed. Usage:

    python data/fetch/fetch_yard_data.py              # fetch all small sources
    python data/fetch/fetch_yard_data.py --only t2015_kcs_case21
    python data/fetch/fetch_yard_data.py --verify-reference   # re-parse KCS/JBC xls and
                                                              # compare with data/reference/*.json

Large datasets (Ship-D 30k, TurtLES 14 TB, AirfRANS, AeroZoo) are NOT fetched by
default; see data/catalog.yaml for their URLs and the sampling notes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "cache"

SOURCES = {
    "t2015_kcs_case21": {
        "url": "https://t2015.nmri.go.jp/Instructions_KCS/Case_2.1/vary_Fr_2-1.xls",
        "file": "t2015_kcs_case21_vary_Fr_2-1.xls",
        "sha256": "37e8bae8eb23f8353abbd1fcf65d14d0a4d5d32e3599054b69797369bda9cfff",
    },
    "t2015_jbc_case11a": {
        "url": "https://t2015.nmri.go.jp/Instructions_JBC/instruction_JBC_files/%5BIdentifier%5D_V&V_1-1a.xls",
        "file": "t2015_jbc_case11a.xls",
        "sha256": "c513ebbc4e18606de433835443b754b11a5b6dc416016fe22909049e1758ccfe",
    },
    "uci_yacht_hydrodynamics": {
        "url": "https://archive.ics.uci.edu/static/public/243/yacht+hydrodynamics.zip",
        "file": "uci_yacht_hydrodynamics.zip",
        "sha256": "aa52b68f88c4bb552187a53ef4c5753fa178f6a36035a3771c5bc04e078487ac",
    },
    "t2015_kcs_hull_sva": {
        "url": "https://t2015.nmri.go.jp/file/Geometry_IGES_files/kcs/KCS_hull_SVA.zip",
        "file": "t2015_kcs_hull_sva.zip",
        "sha256": "b9e334853857b819bbddfd549f4599dde7cba57a9540893b873aaae56dc99a20",
    },
    "g2000_kvlcc2_offsets": {
        "url": "https://www.nmri.go.jp/study/research_organization/fluid_performance/cfd/cfdws05/gothenburg2000/data/KVLCC2_data/kvlcc2_offsets.ZIP",
        "file": "g2000_kvlcc2_offsets.zip",
        "sha256": "693dfc1b07fe4759e2fa98ff8b6ac66c47ac579d14afae3f253a157d58a6e01f",
    },
    "g2000_dtmb5415_surface_grid": {
        "url": "https://www.nmri.go.jp/study/research_organization/fluid_performance/cfd/cfdws05/gothenburg2000/data/5415/5415_static.net",
        "file": "g2000_dtmb5415_static.net",
        "sha256": "6cda8ea29d4efecab814737d32d487916ed7ba5cbbc85242e77a44ba36612a34",
    },
    "dsyhs_modelscale": {
        "url": "https://data.4tu.nl/file/d0db7d79-a31d-492d-95a1-30dd9a17063f/19ef2212-90f9-4e95-b1cd-9b5ef410ef16",
        "file": "DSYHS_all_measurements_modelscale.xlsx",
        "sha256": "d8e03c1185717d783199723ba0cdf5bbc55b16f31508805f7ea9c6911f6b86d3",
    },
    "dsyhs_overview": {
        "url": "https://data.4tu.nl/file/d0db7d79-a31d-492d-95a1-30dd9a17063f/db3ad96b-37db-419e-a5ad-1ac9d83f8a9d",
        "file": "DSYHS_overview_performed_tests.xlsx",
        "sha256": "bc671656085140c692e0d222ccf56228d5f46ec710003cc0400b0b953a6086a7",
    },
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(key: str, *, force: bool = False) -> Path:
    src = SOURCES[key]
    CACHE.mkdir(parents=True, exist_ok=True)
    dest = CACHE / src["file"]
    if force or not dest.exists():
        req = urllib.request.Request(src["url"], headers={"User-Agent": "yard-data-fetch/1"})
        with urllib.request.urlopen(req, timeout=120) as r:
            dest.write_bytes(r.read())
    got = sha256(dest)
    if got != src["sha256"]:
        raise SystemExit(f"{key}: sha256 mismatch {got} != {src['sha256']} (upstream changed? re-verify before updating)")
    return dest


def verify_reference() -> int:
    """Re-parse the fetched Tokyo 2015 spreadsheets and compare with the cited reference JSON."""
    try:
        import pandas as pd  # noqa: F401
    except ImportError:
        print("pandas + xlrd needed for --verify-reference", file=sys.stderr)
        return 2
    import pandas as pd

    ref = json.loads((ROOT / "reference" / "tank_resistance_reference.json").read_text())
    bad = 0
    kcs = pd.read_excel(fetch("t2015_kcs_case21"), header=None).to_numpy()
    rows = [(float(r[2]), float(r[3])) for r in kcs if isinstance(r[2], (int, float)) and r[2] == r[2]]
    want = [(p["Fn"], p["CT"] * 1e3) for p in ref["hulls"]["KCS"]["points"]]
    if [(round(a, 3), round(b, 3)) for a, b in rows] != [(round(a, 3), round(b, 3)) for a, b in want]:
        print("KCS mismatch:", rows, want)
        bad += 1
    jbc = pd.read_excel(fetch("t2015_jbc_case11a"), header=None).to_numpy()
    ct = [r[2] for r in jbc if str(r[0]).startswith("CT")][0]
    if round(float(ct), 3) != round(ref["hulls"]["JBC"]["points"][0]["CT"] * 1e3, 3):
        print("JBC mismatch:", ct)
        bad += 1
    print("reference verified" if not bad else f"{bad} mismatches")
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", action="append")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--verify-reference", action="store_true")
    a = ap.parse_args()
    if a.verify_reference:
        return verify_reference()
    for k in a.only or SOURCES:
        p = fetch(k, force=a.force)
        print(f"ok {k} -> {p.relative_to(ROOT.parent)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
