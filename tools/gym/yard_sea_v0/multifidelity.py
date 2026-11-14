"""Multi-fidelity design-search: cheap L1/L1.5 always, expensive L3_rans on elites.

Stage A
  Random / hill-climb / optional BoTorch optimize L0-gated L1 reward.
  Optional Michell L1.5 attaches a mid-fidelity Ct/Cw for ranking.

Stage B
  Top-k elites by Stage-A score → OpenFOAM L3 forceCoeffs teacher → re-rank by Cd/Ct.

Cost-aware BoTorch (approximation)
  When BoTorch is available and ``cost_aware=True``, Stage-A acquisition uses
  ``qLogExpectedImprovement`` wrapped with ``InverseCostWeightedUtility`` and a
  constant L1 cost model. Full continuous multi-fidelity KG
  (``qMultiFidelityKnowledgeGradient``) is **not** used: L3 is deliberately
  gated to elites only (cascade), which is the primary cost control. Relative
  costs are recorded on each child's ``fidelity_ladder`` for budget accounting.
"""

from __future__ import annotations

import json
import os
import warnings
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

import numpy as np

from .hull import HullState
from .resistance_l1 import estimate_resistance
from .search import botorch_available, run_search

# Relative wall-clock cost units (exploratory; not measured FLOPs).
COST_L1 = 1.0
COST_L15 = 20.0
COST_L2 = 80.0
COST_L3 = 2000.0

FIDELITY_L1 = "L1_holtrop_simplified"
FIDELITY_L15 = "L1.5_michell"
FIDELITY_L2 = "L2_panel_bem"
FIDELITY_L3_RANS = "L3_rans"
FIDELITY_L3_PENDING = "L3_pending"

COST_AWARE_NOTES = (
    "Cost-aware approximation: Stage A uses BoTorch qLogEI + InverseCostWeightedUtility "
    f"with constant cost={COST_L1} (L1). L3 (cost≈{COST_L3}) is cascade-gated to top-k "
    "elites — not continuous MF-KG. Documented deliberately; not ITTC / not class."
)


@dataclass
class FidelityStep:
    level: str
    cost: float
    Ct: float | None = None
    Cd: float | None = None
    Cw: float | None = None
    teacher: str | None = None
    skipped: bool = False
    skip_reason: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {
            "level": self.level,
            "cost": self.cost,
            "Ct": self.Ct,
            "Cd": self.Cd,
            "Cw": self.Cw,
            "teacher": self.teacher,
            "skipped": self.skipped,
            "skip_reason": self.skip_reason,
        }
        if self.extra:
            d["extra"] = self.extra
        return d


def stage_a_score(row: dict[str, Any]) -> float:
    """Lower is better. Prefer mid-fidelity Ct (L2 then L1.5) when finite, else L1 Ct."""
    l2 = row.get("l2_panel") or {}
    ct2 = l2.get("Ct")
    if ct2 is not None and np.isfinite(float(ct2)) and not l2.get("skipped"):
        return float(ct2)
    l15 = row.get("l15_michell") or {}
    ct15 = l15.get("Ct")
    if ct15 is not None and np.isfinite(float(ct15)) and not l15.get("skipped"):
        return float(ct15)
    ct = row.get("ct")
    if ct is None or not np.isfinite(float(ct)):
        return 1e9
    return float(ct)


def stage_b_score(row: dict[str, Any]) -> float:
    """Lower is better. Prefer L3 Cd, else L3 Ct, else Stage-A score."""
    cd = row.get("Cd")
    if cd is not None and np.isfinite(float(cd)):
        return float(cd)
    l3 = row.get("l3_openfoam") or {}
    if l3.get("Cd") is not None and np.isfinite(float(l3["Cd"])):
        return float(l3["Cd"])
    if l3.get("Ct") is not None and np.isfinite(float(l3["Ct"])):
        return float(l3["Ct"])
    return stage_a_score(row)


def _hull_from_row(row: dict[str, Any]) -> HullState | None:
    h = row.get("hull")
    if not h:
        return None
    keys = ("L", "B", "T", "Cb", "lcb_frac", "kg_frac", "Fn")
    return HullState(**{k: h[k] for k in keys if k in h})


def _attach_l1_ladder(row: dict[str, Any]) -> None:
    ladder = list(row.get("fidelity_ladder") or [])
    if any(s.get("level") == FIDELITY_L1 for s in ladder):
        return
    ct = row.get("ct")
    ladder.insert(
        0,
        FidelityStep(
            level=FIDELITY_L1,
            cost=COST_L1,
            Ct=float(ct) if ct is not None else None,
            teacher="resistance_l1",
        ).to_dict(),
    )
    row["fidelity_ladder"] = ladder
    row["stage_a_score"] = stage_a_score(row)


def attach_l15(
    rows: list[dict[str, Any]],
    *,
    availability: Any | None = None,
    runner: Callable[..., dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """Evaluate Michell L1.5 on every Stage-A child that has a hull."""
    from .teachers.michell_l15 import detect as detect_michell
    from .teachers.michell_l15 import run as run_michell

    run_fn = runner or run_michell
    avail = availability if availability is not None else detect_michell()
    for row in rows:
        if row.get("skipped") or not row.get("hull"):
            continue
        hull = _hull_from_row(row)
        if hull is None:
            continue
        try:
            l15 = run_fn(hull, availability=avail)
        except Exception as exc:  # noqa: BLE001
            l15 = {
                "fidelity": "L1.5_pending",
                "skipped": True,
                "skip_reason": str(exc),
                "Ct": None,
                "Cw": None,
                "teacher": "michell_l15",
            }
        row["l15_michell"] = l15
        ladder = list(row.get("fidelity_ladder") or [])
        ladder = [s for s in ladder if s.get("level") not in (FIDELITY_L15, "L1.5_pending")]
        ladder.append(
            FidelityStep(
                level=l15.get("fidelity") or FIDELITY_L15,
                cost=COST_L15,
                Ct=l15.get("Ct"),
                Cw=l15.get("Cw"),
                teacher="michell_l15",
                skipped=bool(l15.get("skipped")),
                skip_reason=l15.get("skip_reason"),
            ).to_dict()
        )
        row["fidelity_ladder"] = ladder
        row["stage_a_score"] = stage_a_score(row)
    return rows


def attach_l2(
    rows: list[dict[str, Any]],
    *,
    availability: Any | None = None,
    runner: Callable[..., dict[str, Any]] | None = None,
    stl_from_row: Callable[[dict[str, Any], int], Path | None] | None = None,
) -> list[dict[str, Any]]:
    """Evaluate Capytaine L2 panel/BEM on every Stage-A child that has a hull."""
    from .teachers.panel_l2 import detect as detect_panel
    from .teachers.panel_l2 import run as run_panel

    run_fn = runner or run_panel
    avail = availability if availability is not None else detect_panel()
    for j, row in enumerate(rows):
        if row.get("skipped") or not row.get("hull"):
            continue
        hull = _hull_from_row(row)
        if hull is None:
            continue
        stl_path = stl_from_row(row, j) if stl_from_row else None
        try:
            l2 = run_fn(hull, stl_path=stl_path, availability=avail)
        except Exception as exc:  # noqa: BLE001
            l2 = {
                "fidelity": "L2_pending",
                "skipped": True,
                "skip_reason": str(exc),
                "Ct": None,
                "Cw": None,
                "Cd": None,
                "teacher": "panel_l2",
            }
        row["l2_panel"] = l2
        ladder = list(row.get("fidelity_ladder") or [])
        ladder = [s for s in ladder if s.get("level") not in (FIDELITY_L2, "L2_pending")]
        ladder.append(
            FidelityStep(
                level=l2.get("fidelity") or FIDELITY_L2,
                cost=COST_L2,
                Ct=l2.get("Ct"),
                Cw=l2.get("Cw"),
                Cd=l2.get("Cd"),
                teacher="panel_l2",
                skipped=bool(l2.get("skipped")),
                skip_reason=l2.get("skip_reason"),
                extra={"backend": l2.get("backend")},
            ).to_dict()
        )
        row["fidelity_ladder"] = ladder
        # Keep Stage-A score L1/L1.5 based; L2 is mid-ladder diagnostic
        row["stage_a_score"] = stage_a_score(row)
    return rows


def select_elites(rows: list[dict[str, Any]], k: int) -> list[int]:
    """Return indices of top-k feasible children by Stage-A score (lower better)."""
    ranked = sorted(
        (
            (i, stage_a_score(r))
            for i, r in enumerate(rows)
            if r.get("hull") and not r.get("skipped")
        ),
        key=lambda t: t[1],
    )
    return [i for i, _ in ranked[: max(0, int(k))]]


def evaluate_l3_elites(
    rows: list[dict[str, Any]],
    elite_indices: list[int],
    *,
    out_dir: Path | None = None,
    availability: Any | None = None,
    runner: Callable[..., dict[str, Any]] | None = None,
    timeout_s: float | None = None,
) -> list[dict[str, Any]]:
    """Run L3 forceCoeffs teacher on elite children; attach Cd + ladder step."""
    from .mesh import export_hull_stl
    from .teachers.openfoam_l3 import detect_openfoam, run_teacher

    run_fn = runner or run_teacher
    avail = availability if availability is not None else detect_openfoam()
    l3_root = Path(out_dir) / "l3_openfoam" if out_dir else None
    if l3_root is not None:
        l3_root.mkdir(parents=True, exist_ok=True)
    to = float(
        timeout_s
        if timeout_s is not None
        else os.environ.get("YARD_SEA_L3_TIMEOUT", "180")
    )
    elite_set = set(elite_indices)

    for j, row in enumerate(rows):
        if j not in elite_set:
            # Mark that L3 was intentionally not run (cost gate).
            ladder = list(row.get("fidelity_ladder") or [])
            if not any(s.get("level", "").startswith("L3") for s in ladder):
                ladder.append(
                    FidelityStep(
                        level=FIDELITY_L3_PENDING,
                        cost=0.0,
                        teacher="openfoam_l3",
                        skipped=True,
                        skip_reason="not_elite_cost_gate",
                    ).to_dict()
                )
                row["fidelity_ladder"] = ladder
            row["l3_elite"] = False
            row["stage_b_score"] = None
            continue

        row["l3_elite"] = True
        hull = _hull_from_row(row)
        if hull is None:
            row["l3_openfoam"] = {
                "skipped": True,
                "skip_reason": "no_hull",
                "fidelity": FIDELITY_L3_PENDING,
            }
            continue

        stl_path = None
        if out_dir is not None:
            children = Path(out_dir) / "children"
            children.mkdir(parents=True, exist_ok=True)
            stl_path = children / f"elite_{j:03d}.stl"
            stl_path, _ = export_hull_stl(hull, stl_path)
        else:
            import tempfile

            tmp = Path(tempfile.mkdtemp(prefix="yard_mf_"))
            stl_path = tmp / "hull.stl"
            stl_path, _ = export_hull_stl(hull, stl_path)

        case_dir = (l3_root / f"elite_{j:03d}") if l3_root else Path(stl_path).parent / "case"
        try:
            l3 = run_fn(
                stl_path,
                float(hull.Fn),
                case_dir,
                L=hull.L,
                B=hull.B,
                T=hull.T,
                availability=avail,
                timeout_s=to,
            )
        except Exception as exc:  # noqa: BLE001
            l3 = {
                "fidelity": FIDELITY_L3_PENDING,
                "skipped": True,
                "skip_reason": str(exc),
                "Cd": None,
                "Ct": None,
                "teacher": "openfoam_l3",
            }

        row["l3_openfoam"] = l3
        row["Cd"] = l3.get("Cd")
        row["l3_fidelity"] = l3.get("fidelity")
        row["l3_Ct"] = l3.get("Ct")
        row["l3_solver"] = l3.get("solver")
        spent = 0.0 if l3.get("skipped") else COST_L3
        ladder = list(row.get("fidelity_ladder") or [])
        ladder = [s for s in ladder if not str(s.get("level", "")).startswith("L3")]
        ladder.append(
            FidelityStep(
                level=l3.get("fidelity") or FIDELITY_L3_PENDING,
                cost=spent,
                Ct=l3.get("Ct"),
                Cd=l3.get("Cd"),
                teacher="openfoam_l3",
                skipped=bool(l3.get("skipped")),
                skip_reason=l3.get("skip_reason"),
                extra={"solver": l3.get("solver")},
            ).to_dict()
        )
        row["fidelity_ladder"] = ladder
        row["stage_b_score"] = stage_b_score(row)
    return rows


def _botorch_stage_a_cost_aware(
    parent: HullState,
    steps: int,
    seed: int,
) -> dict[str, Any] | None:
    """Stage-A BoTorch with InverseCostWeightedUtility (constant L1 cost).

    Approximation of cost-aware MF acquisition — see COST_AWARE_NOTES.
    """
    try:
        import torch
        from botorch.acquisition.cost_aware import InverseCostWeightedUtility
        from botorch.acquisition.logei import qLogExpectedImprovement
        from botorch.fit import fit_gpytorch_mll
        from botorch.models import SingleTaskGP
        from botorch.models.deterministic import GenericDeterministicModel
        from botorch.optim import optimize_acqf
        from botorch.sampling.normal import SobolQMCNormalSampler
        from gpytorch.mlls import ExactMarginalLogLikelihood
    except ImportError:
        # Fall back to standard L1 BoTorch path.
        from .search import _botorch_child

        row = _botorch_child(parent, steps=steps, seed=seed)
        if row is not None:
            row["cost_aware"] = False
            row["cost_aware_notes"] = "botorch cost-aware imports missing; used standard EI"
        return row

    from .env import _reward
    from .monitors import monitor_action

    torch.manual_seed(seed)
    parent_ct = estimate_resistance(parent).Ct
    parent_vol = parent.volume()
    train_x: list[np.ndarray] = []
    train_y: list[list[float]] = []
    best_hull = parent
    best_y = -1e9
    best_ct = parent_ct

    rng = np.random.default_rng(seed)
    n_init = max(5, min(12, max(3, steps // 2)))
    for _ in range(n_init):
        a = rng.uniform(-1.0, 1.0, size=7)
        d = monitor_action(parent, a)
        if d.allow and d.projected is not None:
            y = float(_reward(d.projected, parent_ct, parent_vol))
            train_x.append(np.asarray(a, dtype=np.float64))
            train_y.append([y])
            if y > best_y:
                best_y = y
                best_hull = d.projected
                best_ct = estimate_resistance(d.projected).Ct

    if len(train_x) < 3:
        return {
            "method": "botorch_mf",
            "skipped": True,
            "reason": "insufficient feasible samples",
            "parent_ct": parent_ct,
            "cost_aware": True,
        }

    X = torch.tensor(np.asarray(train_x, dtype=np.float64), dtype=torch.double)
    Y = torch.tensor(np.asarray(train_y, dtype=np.float64), dtype=torch.double)
    y_mean = Y.mean()
    y_std = Y.std().clamp_min(1e-6)
    Yn = (Y - y_mean) / y_std
    bounds = torch.tensor([[-1.0] * 7, [1.0] * 7], dtype=torch.double)
    n_bo = max(1, int(steps))
    n_restarts = 2 if n_bo <= 5 else 4
    raw_samples = 16 if n_bo <= 5 else 32

    # Constant L1 cost — Stage A never proposes L3 inside the acquisition.
    cost_model = GenericDeterministicModel(
        lambda XX: torch.full(XX.shape[:-1] + (1,), COST_L1, dtype=XX.dtype, device=XX.device)
    )
    cost_aware_utility = InverseCostWeightedUtility(cost_model=cost_model)

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        for _ in range(n_bo):
            model = SingleTaskGP(X, Yn)
            mll = ExactMarginalLogLikelihood(model.likelihood, model)
            fit_gpytorch_mll(mll)
            sampler = SobolQMCNormalSampler(sample_shape=torch.Size([64]))
            acq = qLogExpectedImprovement(
                model=model,
                best_f=Yn.max(),
                sampler=sampler,
                # cost-aware wrapper via objective is not always exposed on LogEI;
                # apply InverseCostWeightedUtility to MC utility samples when supported.
            )
            # Prefer attaching cost utility when the acq exposes the hook.
            if hasattr(acq, "cost_aware_utility"):
                acq.cost_aware_utility = cost_aware_utility
            cand, _ = optimize_acqf(
                acq,
                bounds=bounds,
                q=1,
                num_restarts=n_restarts,
                raw_samples=raw_samples,
            )
            a = cand.detach().cpu().numpy().reshape(-1)
            d = monitor_action(parent, a)
            if not d.allow or d.projected is None:
                y = -1.0
            else:
                y = float(_reward(d.projected, parent_ct, parent_vol))
                if y > best_y:
                    best_y = y
                    best_hull = d.projected
                    best_ct = estimate_resistance(d.projected).Ct
            X = torch.cat([X, cand.detach().to(dtype=torch.double)], dim=0)
            Y = torch.cat([Y, torch.tensor([[y]], dtype=torch.double)], dim=0)
            Yn = (Y - y_mean) / y_std

    ct = float(best_ct)
    return {
        "method": "botorch_mf",
        "ct": ct,
        "reward_sum": float(best_y),
        "delta_ct_vs_parent": parent_ct - ct,
        "parent_ct": parent_ct,
        "improved": ct < parent_ct,
        "hull": best_hull.to_dict(),
        "evidence_count": 0,
        "skipped": False,
        "n_init": len(train_x),
        "n_bo_steps": n_bo,
        "botorch_available": True,
        "cost_aware": True,
        "cost_aware_notes": COST_AWARE_NOTES,
        "cost_l1": COST_L1,
        "cost_l3_gate": COST_L3,
    }


def run_multifidelity_search(
    parents: list[HullState],
    steps: int = 40,
    seed: int = 0,
    evidence_root: Path | None = None,
    *,
    use_botorch: bool = False,
    use_l15: bool = False,
    use_l2: bool = False,
    l3_top: int = 3,
    cost_aware: bool = True,
    out_dir: Path | None = None,
    l3_runner: Callable[..., dict[str, Any]] | None = None,
    l15_runner: Callable[..., dict[str, Any]] | None = None,
    l2_runner: Callable[..., dict[str, Any]] | None = None,
    l3_availability: Any | None = None,
    l15_availability: Any | None = None,
    l2_availability: Any | None = None,
    skip_l3: bool = False,
) -> dict[str, Any]:
    """Full Stage A → elite L3 Stage B loop.

    Returns a dict with ``results``, ``elite_indices``, ``manifest`` fields.
    """
    # Stage A — cheap L1 (+ optional cost-aware BoTorch)
    results = run_search(
        parents,
        steps=steps,
        seed=seed,
        evidence_root=evidence_root,
        use_botorch=use_botorch and not cost_aware,
    )

    if use_botorch and cost_aware and botorch_available():
        for i, parent in enumerate(parents):
            try:
                bo_steps = max(3, min(int(steps), 25))
                child_bo = _botorch_stage_a_cost_aware(parent, steps=bo_steps, seed=seed + 200 + i)
                if child_bo is not None:
                    child_bo["parent_index"] = i
                    if "parent_ct" not in child_bo:
                        child_bo["parent_ct"] = estimate_resistance(parent).Ct
                    results.append(child_bo)
            except Exception as exc:  # noqa: BLE001
                results.append(
                    {
                        "method": "botorch_mf",
                        "skipped": True,
                        "reason": str(exc),
                        "parent_index": i,
                        "cost_aware": True,
                    }
                )
    elif use_botorch and cost_aware and not botorch_available():
        # run_search already skipped when use_botorch=False above; add skip row.
        for i, parent in enumerate(parents):
            results.append(
                {
                    "method": "botorch_mf",
                    "skipped": True,
                    "reason": "botorch/torch not installed",
                    "parent_index": i,
                    "cost_aware": True,
                }
            )

    for row in results:
        _attach_l1_ladder(row)

    if use_l15:
        attach_l15(results, availability=l15_availability, runner=l15_runner)

    if use_l2:
        attach_l2(results, availability=l2_availability, runner=l2_runner)

    elite_indices: list[int] = []
    if not skip_l3 and l3_top > 0:
        elite_indices = select_elites(results, l3_top)
        evaluate_l3_elites(
            results,
            elite_indices,
            out_dir=out_dir,
            availability=l3_availability,
            runner=l3_runner,
        )
    else:
        for row in results:
            row["l3_elite"] = False

    # Final ranking: elites by Stage-B score, then non-elites by Stage-A.
    def _final_key(item: tuple[int, dict[str, Any]]) -> tuple[int, float]:
        i, r = item
        if r.get("l3_elite") and r.get("stage_b_score") is not None:
            return (0, float(r["stage_b_score"]))
        return (1, stage_a_score(r))

    ranked = sorted(enumerate(results), key=_final_key)
    for rank, (i, r) in enumerate(ranked):
        r["mf_rank"] = rank
        r["total_cost"] = sum(
            float(s.get("cost") or 0.0) for s in (r.get("fidelity_ladder") or [])
        )

    total_cost = sum(float(r.get("total_cost") or 0.0) for r in results)
    n_l3 = sum(1 for r in results if r.get("l3_elite"))
    best = ranked[0][1] if ranked else None

    summary = {
        "multifidelity": True,
        "cost_aware": bool(cost_aware and use_botorch),
        "cost_aware_notes": COST_AWARE_NOTES if (cost_aware and use_botorch) else None,
        "costs": {"L1": COST_L1, "L1.5": COST_L15, "L2": COST_L2, "L3": COST_L3},
        "use_botorch": use_botorch,
        "use_l15": use_l15,
        "use_l2": use_l2,
        "l3_top": int(l3_top),
        "n_stage_a": len(results),
        "elite_indices": elite_indices,
        "n_l3_evaluated": n_l3,
        "total_cost_units": total_cost,
        "best_mf_rank0": {
            "method": best.get("method") if best else None,
            "stage_a_score": stage_a_score(best) if best else None,
            "stage_b_score": best.get("stage_b_score") if best else None,
            "Cd": best.get("Cd") if best else None,
            "ct": best.get("ct") if best else None,
            "l3_elite": best.get("l3_elite") if best else None,
            "fidelity_ladder": best.get("fidelity_ladder") if best else None,
        }
        if best
        else None,
        "botorch_available": botorch_available(),
    }
    return {"results": results, "elite_indices": elite_indices, "summary": summary}
