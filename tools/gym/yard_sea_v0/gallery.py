"""Write parent→child gallery artifacts."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .hull import HullState
from .resistance_l1 import estimate_resistance
from .search import run_search
from .shipd import load_sample_vectors, project_to_hull
from .mesh import export_hull_stl
from .teachers.openfoam_l3 import detect_openfoam, run_teacher


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


def shipd_parents(n: int = 5) -> list[HullState]:
    """Seed parents from public Ship-D sample vectors (projected).

    Prefers vectors that pass Ship-D 49 algebraic constraints, then L0.
    """
    samples = load_sample_vectors()
    out: list[HullState] = []
    from .hull import evaluate_l0
    from .shipd_surface import evaluate_constraints

    for v in samples:
        if not evaluate_constraints(v).feasible:
            continue
        h = project_to_hull(v)
        if evaluate_l0(h).feasible:
            out.append(h)
        if len(out) >= n:
            break
    if len(out) < n:
        out.extend(default_parents(n - len(out), seed=1))
    return out[:n]


def write_gallery(
    out_dir: Path,
    n_parents: int = 5,
    steps: int = 40,
    seed: int = 0,
    use_shipd: bool = False,
    use_corpus: bool = False,
    l3_openfoam: bool = False,
) -> dict[str, Any]:
    out_dir = Path(out_dir)
    children_dir = out_dir / "children"
    evidence_dir = out_dir / "evidence"
    children_dir.mkdir(parents=True, exist_ok=True)
    if use_corpus:
        from .corpus import sample_parents as corpus_parents

        parents = corpus_parents(n_parents, seed=seed)
    elif use_shipd:
        parents = shipd_parents(n_parents)
    else:
        parents = default_parents(n_parents, seed=seed)
    parent_meta = []
    for i, p in enumerate(parents):
        r = estimate_resistance(p)
        parent_meta.append({"index": i, "ct": r.Ct, "hull": p.to_dict()})
    results = run_search(parents, steps=steps, seed=seed, evidence_root=evidence_dir)
    improved = [r for r in results if r.get("improved")]
    l3_dir = out_dir / "l3_openfoam"
    l3_summaries: list[dict[str, Any]] = []
    avail = detect_openfoam() if l3_openfoam else None
    for j, r in enumerate(results):
        (children_dir / f"child_{j:03d}.json").write_text(json.dumps(r, indent=2, sort_keys=True))
        stl_path = None
        if r.get("hull"):
            from .hull import HullState
            stl_path = children_dir / f"child_{j:03d}.stl"
            stl_path, _mesh_backend = export_hull_stl(HullState(**{k: r["hull"][k] for k in ("L","B","T","Cb","lcb_frac","kg_frac","Fn") if k in r["hull"]}), stl_path)
        if l3_openfoam and stl_path is not None:
            hull = r["hull"]
            l3 = run_teacher(
                stl_path,
                float(hull.get("Fn", 0.2)),
                l3_dir / f"child_{j:03d}",
                L=hull.get("L"),
                B=hull.get("B"),
                T=hull.get("T"),
                availability=avail,
            )
            r["l3_openfoam"] = l3
            (children_dir / f"child_{j:03d}.json").write_text(json.dumps(r, indent=2, sort_keys=True))
            l3_summaries.append(
                {
                    "child": j,
                    "fidelity": l3.get("fidelity"),
                    "skipped": l3.get("skipped"),
                    "skip_reason": l3.get("skip_reason"),
                    "Cd": l3.get("Cd"),
                }
            )
    manifest = {
        "n_parents": n_parents,
        "steps": steps,
        "seed": seed,
        "use_shipd": use_shipd,
        "use_corpus": use_corpus,
        "l3_openfoam": l3_openfoam,
        "l3_availability": avail.to_dict() if avail else None,
        "l3_summaries": l3_summaries,
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
        f"- L3 OpenFOAM: {'on' if l3_openfoam else 'off'}"
        + (
            f" (available={avail.available})" if avail else ""
        ),
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
