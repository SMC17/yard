"""Write parent→child gallery artifacts."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .hull import HullState
from .resistance_l1 import estimate_resistance
from .search import run_search


def default_parents(n: int = 5, seed: int = 0) -> list[HullState]:
    import numpy as np

    rng = np.random.default_rng(seed)
    base = HullState()
    parents = [base]
    for _ in range(n - 1):
        parents.append(
            HullState(
                L=float(rng.uniform(80, 180)),
                B=float(rng.uniform(14, 28)),
                T=float(rng.uniform(5, 11)),
                Cb=float(rng.uniform(0.65, 0.85)),
                lcb_frac=float(rng.uniform(-0.03, 0.03)),
                kg_frac=float(rng.uniform(0.5, 0.6)),
                Fn=float(rng.uniform(0.16, 0.24)),
            )
        )
    return parents


def write_gallery(
    out_dir: Path,
    n_parents: int = 5,
    steps: int = 40,
    seed: int = 0,
) -> dict[str, Any]:
    out_dir = Path(out_dir)
    children_dir = out_dir / "children"
    evidence_dir = out_dir / "evidence"
    children_dir.mkdir(parents=True, exist_ok=True)
    parents = default_parents(n_parents, seed=seed)
    parent_meta = []
    for i, p in enumerate(parents):
        r = estimate_resistance(p)
        parent_meta.append({"index": i, "ct": r.Ct, "hull": p.to_dict()})
    results = run_search(parents, steps=steps, seed=seed, evidence_root=evidence_dir)
    improved = [r for r in results if r.get("improved")]
    for j, r in enumerate(results):
        (children_dir / f"child_{j:03d}.json").write_text(json.dumps(r, indent=2, sort_keys=True))
    manifest = {
        "n_parents": n_parents,
        "steps": steps,
        "seed": seed,
        "n_results": len(results),
        "n_improved": len(improved),
        "parents": parent_meta,
        "best_delta_ct": max((r.get("delta_ct_vs_parent") or -1e9) for r in results if "delta_ct_vs_parent" in r),
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True))
    lines = [
        "# Yard-Sea-v0 gallery",
        "",
        f"- Parents: {n_parents}",
        f"- Results: {len(results)}",
        f"- Improved Ct vs parent: {len(improved)}",
        f"- Best ΔCt: {manifest['best_delta_ct']:.6f}",
        "",
        "Fidelity: L0 monitors + L1 Holtrop-simplified. Not ITTC powering / not class.",
        "",
    ]
    for r in sorted(
        [x for x in results if "ct" in x],
        key=lambda z: z.get("delta_ct_vs_parent") or -1e9,
        reverse=True,
    )[:10]:
        lines.append(
            f"- {r.get('method')} parent={r.get('parent_index')} "
            f"ΔCt={r.get('delta_ct_vs_parent'):.6f} Ct={r.get('ct'):.6f}"
        )
    (out_dir / "summary.md").write_text("\n".join(lines) + "\n")
    return manifest
