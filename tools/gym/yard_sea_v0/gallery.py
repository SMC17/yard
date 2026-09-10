"""Write parent→child gallery artifacts."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from .hull import HullState
from .resistance_l1 import estimate_resistance
from .search import run_search
from .shipd import load_sample_vectors, project_to_hull
from .mesh import export_hull_stl
from .teachers.openfoam_l3 import detect_openfoam, run_teacher
from .teachers.michell_l15 import detect as detect_michell, run as run_michell
from .teachers.panel_l2 import detect as detect_panel, run as run_panel


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
    """Seed parents from public Ship-D sample vectors (HP primary).

    Prefers HP ``calc_volumes`` HullState; falls back to ``project_to_hull``.
    Only vectors that pass Ship-D 49 algebraic constraints, then L0.
    """
    samples = load_sample_vectors()
    out: list[HullState] = []
    from .hp_rank import hull_from_shipd_primary
    from .hull import evaluate_l0
    from .shipd_surface import evaluate_constraints

    for v in samples:
        if not evaluate_constraints(v).feasible:
            continue
        h, _src, _vol, _reason = hull_from_shipd_primary(v, prefer_hp=True)
        if evaluate_l0(h).feasible:
            out.append(h)
        if len(out) >= n:
            break
    if len(out) < n:
        out.extend(default_parents(n - len(out), seed=1))
    return out[:n]


def shipd_parent_vectors(n: int = 5) -> list:
    """Feasible Ship-D sample vectors aligned with ``shipd_parents`` selection."""
    samples = load_sample_vectors()
    from .hp_rank import hull_from_shipd_primary
    from .hull import evaluate_l0
    from .shipd_surface import evaluate_constraints

    out = []
    for v in samples:
        if not evaluate_constraints(v).feasible:
            continue
        h, _, _, _ = hull_from_shipd_primary(v, prefer_hp=True)
        if evaluate_l0(h).feasible:
            out.append(v)
        if len(out) >= n:
            break
    return out


def write_gallery(
    out_dir: Path,
    n_parents: int = 5,
    steps: int = 40,
    seed: int = 0,
    use_shipd: bool = False,
    use_corpus: bool = False,
    l3_openfoam: bool = False,
    l15_michell: bool = False,
    l2_panel: bool = False,
    use_botorch: bool = False,
    multifidelity: bool = False,
    l3_top: int = 3,
    cost_aware: bool = True,
) -> dict[str, Any]:
    out_dir = Path(out_dir)
    children_dir = out_dir / "children"
    evidence_dir = out_dir / "evidence"
    children_dir.mkdir(parents=True, exist_ok=True)
    shipd_vecs = None
    if use_corpus:
        from .corpus import sample_parents as corpus_parents

        parents = corpus_parents(n_parents, seed=seed)
    elif use_shipd:
        parents = shipd_parents(n_parents)
        shipd_vecs = shipd_parent_vectors(n_parents)
    else:
        parents = default_parents(n_parents, seed=seed)
    parent_meta = []
    for i, p in enumerate(parents):
        r = estimate_resistance(p)
        parent_meta.append(
            {
                "index": i,
                "ct": r.Ct,
                "l1_fidelity": r.fidelity,
                "hull": p.to_dict(),
            }
        )
    mf_summary: dict[str, Any] | None = None
    l3_summaries: list[dict[str, Any]] = []
    l15_summaries: list[dict[str, Any]] = []
    l2_summaries: list[dict[str, Any]] = []
    avail = None
    michell_avail = None
    panel_avail = None

    if multifidelity:
        from .multifidelity import run_multifidelity_search

        # Multifidelity: L3 only on top-k elites (cost-gated). L3 is implied by --multifidelity.
        mf = run_multifidelity_search(
            parents,
            steps=steps,
            seed=seed,
            evidence_root=evidence_dir,
            use_botorch=use_botorch,
            use_l15=l15_michell,
            use_l2=l2_panel,
            l3_top=int(l3_top),
            cost_aware=cost_aware,
            out_dir=out_dir,
            skip_l3=False,
        )
        results = mf["results"]
        mf_summary = mf["summary"]
        avail = detect_openfoam()
        michell_avail = detect_michell() if l15_michell else None
        panel_avail = detect_panel() if l2_panel else None
        for j, r in enumerate(results):
            if r.get("l15_michell"):
                l15 = r["l15_michell"]
                l15_summaries.append(
                    {
                        "child": j,
                        "fidelity": l15.get("fidelity"),
                        "skipped": l15.get("skipped"),
                        "Cw": l15.get("Cw"),
                        "Ct": l15.get("Ct"),
                    }
                )
            if r.get("l2_panel"):
                l2 = r["l2_panel"]
                l2_summaries.append(
                    {
                        "child": j,
                        "fidelity": l2.get("fidelity"),
                        "skipped": l2.get("skipped"),
                        "skip_reason": l2.get("skip_reason"),
                        "Cw": l2.get("Cw"),
                        "Cd": l2.get("Cd"),
                        "Ct": l2.get("Ct"),
                        "backend": l2.get("backend"),
                    }
                )
            if r.get("l3_elite") and r.get("l3_openfoam"):
                l3 = r["l3_openfoam"]
                l3_summaries.append(
                    {
                        "child": j,
                        "fidelity": l3.get("fidelity"),
                        "skipped": l3.get("skipped"),
                        "skip_reason": l3.get("skip_reason"),
                        "Cd": l3.get("Cd"),
                        "Ct": l3.get("Ct"),
                        "solver": l3.get("solver"),
                        "elite": True,
                    }
                )
            (children_dir / f"child_{j:03d}.json").write_text(
                json.dumps(r, indent=2, sort_keys=True)
            )
            if r.get("hull"):
                stl_path = children_dir / f"child_{j:03d}.stl"
                export_hull_stl(
                    HullState(
                        **{
                            k: r["hull"][k]
                            for k in ("L", "B", "T", "Cb", "lcb_frac", "kg_frac", "Fn")
                            if k in r["hull"]
                        }
                    ),
                    stl_path,
                )
    else:
        results = run_search(
            parents, steps=steps, seed=seed, evidence_root=evidence_dir, use_botorch=use_botorch
        )
        l3_dir = out_dir / "l3_openfoam"
        avail = detect_openfoam() if l3_openfoam else None
        michell_avail = detect_michell() if l15_michell else None
        panel_avail = detect_panel() if l2_panel else None
        for j, r in enumerate(results):
            (children_dir / f"child_{j:03d}.json").write_text(json.dumps(r, indent=2, sort_keys=True))
            stl_path = None
            if r.get("hull"):
                stl_path = children_dir / f"child_{j:03d}.stl"
                pi = r.get("parent_index")
                used_hp_stl = False
                if shipd_vecs is not None and pi is not None and 0 <= int(pi) < len(shipd_vecs):
                    try:
                        from .mesh import write_shipd_stl

                        stl_path = write_shipd_stl(
                            shipd_vecs[int(pi)],
                            stl_path,
                            num_wl=20,
                            points_per_wl=40,
                            require_feasible=False,
                        )
                        _mesh_backend = "shipd_hp_surface"
                        used_hp_stl = True
                    except Exception:
                        used_hp_stl = False
                if not used_hp_stl:
                    stl_path, _mesh_backend = export_hull_stl(
                        HullState(
                            **{
                                k: r["hull"][k]
                                for k in ("L", "B", "T", "Cb", "lcb_frac", "kg_frac", "Fn")
                                if k in r["hull"]
                            }
                        ),
                        stl_path,
                    )
                r["mesh_backend"] = _mesh_backend
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
                    timeout_s=float(os.environ.get("YARD_SEA_L3_TIMEOUT", "180")),
                )
                r["l3_openfoam"] = l3
                r["Cd"] = l3.get("Cd")
                r["l3_fidelity"] = l3.get("fidelity")
                r["l3_Ct"] = l3.get("Ct")
                r["l3_solver"] = l3.get("solver")
                (children_dir / f"child_{j:03d}.json").write_text(
                    json.dumps(r, indent=2, sort_keys=True)
                )
                l3_summaries.append(
                    {
                        "child": j,
                        "fidelity": l3.get("fidelity"),
                        "skipped": l3.get("skipped"),
                        "skip_reason": l3.get("skip_reason"),
                        "Cd": l3.get("Cd"),
                        "Ct": l3.get("Ct"),
                        "solver": l3.get("solver"),
                    }
                )

            if l15_michell and r.get("hull"):
                from .hull import HullState as _HS

                hh = r["hull"]
                hull_obj = _HS(
                    **{
                        k: hh[k]
                        for k in ("L", "B", "T", "Cb", "lcb_frac", "kg_frac", "Fn")
                        if k in hh
                    }
                )
                pi = r.get("parent_index")
                vec = None
                if shipd_vecs is not None and pi is not None and 0 <= int(pi) < len(shipd_vecs):
                    vec = shipd_vecs[int(pi)]
                if vec is not None:
                    l15 = run_michell(hull_obj, vector=vec, availability=michell_avail)
                else:
                    l15 = run_michell(hull_obj, availability=michell_avail)
                r["l15_michell"] = l15
                (children_dir / f"child_{j:03d}.json").write_text(
                    json.dumps(r, indent=2, sort_keys=True)
                )
                l15_summaries.append(
                    {
                        "child": j,
                        "fidelity": l15.get("fidelity"),
                        "skipped": l15.get("skipped"),
                        "Cw": l15.get("Cw"),
                        "Ct": l15.get("Ct"),
                        "offset_source": l15.get("offset_source"),
                    }
                )

            if l2_panel and r.get("hull"):
                from .hull import HullState as _HS2

                hh2 = r["hull"]
                hull_obj2 = _HS2(
                    **{
                        k: hh2[k]
                        for k in ("L", "B", "T", "Cb", "lcb_frac", "kg_frac", "Fn")
                        if k in hh2
                    }
                )
                l2 = run_panel(
                    hull_obj2,
                    stl_path=stl_path,
                    availability=panel_avail,
                )
                r["l2_panel"] = l2
                (children_dir / f"child_{j:03d}.json").write_text(
                    json.dumps(r, indent=2, sort_keys=True)
                )
                l2_summaries.append(
                    {
                        "child": j,
                        "fidelity": l2.get("fidelity"),
                        "skipped": l2.get("skipped"),
                        "skip_reason": l2.get("skip_reason"),
                        "Cw": l2.get("Cw"),
                        "Cd": l2.get("Cd"),
                        "Ct": l2.get("Ct"),
                        "backend": l2.get("backend"),
                    }
                )

    improved = [r for r in results if r.get("improved")]
    deltas = [r.get("delta_ct_vs_parent") or -1e9 for r in results if "delta_ct_vs_parent" in r]
    manifest = {
        "n_parents": n_parents,
        "steps": steps,
        "seed": seed,
        "use_shipd": use_shipd,
        "use_corpus": use_corpus,
        "use_botorch": use_botorch,
        "multifidelity": multifidelity,
        "l3_top": int(l3_top) if multifidelity else None,
        "cost_aware": bool(cost_aware) if multifidelity else None,
        "l3_openfoam": l3_openfoam or multifidelity,
        "l3_availability": avail.to_dict() if avail else None,
        "l3_summaries": l3_summaries,
        "l15_michell": l15_michell,
        "l15_availability": michell_avail.to_dict() if michell_avail else None,
        "l15_summaries": l15_summaries,
        "l2_panel": l2_panel,
        "l2_availability": panel_avail.to_dict() if panel_avail else None,
        "l2_summaries": l2_summaries,
        "multifidelity_summary": mf_summary,
        "n_results": len(results),
        "n_improved": len(improved),
        "parents": parent_meta,
        "l1_fidelity_default": (parent_meta[0].get("l1_fidelity") if parent_meta else None),
        "best_delta_ct": max(deltas) if deltas else -1e9,
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
        "Fidelity: L0 monitors + L1 default Zig HM1984 (hm1984_zig) when yard_sea_zig present; "
        "else Python Holtrop-simplified (simplified_py). Not ITTC powering / not class.",
        f"- BoTorch: {'on' if use_botorch else 'off'}",
        f"- Multifidelity: {'on' if multifidelity else 'off'}"
        + (f" (l3_top={l3_top}, cost_aware={cost_aware})" if multifidelity else ""),
        f"- L3 OpenFOAM: {'on' if (l3_openfoam or multifidelity) else 'off'}"
        + (
            f" (available={avail.available})" if avail else ""
        ),
        f"- L1.5 Michell: {'on' if l15_michell else 'off'}"
        + (
            f" (available={michell_avail.available})" if michell_avail else ""
        ),
        f"- L2 panel/BEM: {'on' if l2_panel else 'off'}"
        + (
            f" (available={panel_avail.available})" if panel_avail else ""
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
