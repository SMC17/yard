"""Search baselines: random, hill-climb, optional BoTorch."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from .env import DesignSearchEnv
from .hull import HullState
from .resistance_l1 import estimate_resistance


@dataclass
class ChildResult:
    hull: HullState
    ct: float
    reward_sum: float
    method: str
    evidence_count: int

    def to_dict(self) -> dict[str, Any]:
        return {
            "method": self.method,
            "ct": self.ct,
            "reward_sum": self.reward_sum,
            "evidence_count": self.evidence_count,
            "delta_ct_vs_parent": None,
            "hull": self.hull.to_dict(),
        }


def _run_episode(env: DesignSearchEnv, policy, steps: int) -> ChildResult:
    obs, info = env.reset()
    total_r = 0.0
    for _ in range(steps):
        action = policy(obs, env)
        obs, reward, term, trunc, info = env.step(action)
        total_r += float(reward)
        if term or trunc:
            break
    ct = estimate_resistance(env.state).Ct
    return ChildResult(
        hull=env.state,
        ct=ct,
        reward_sum=total_r,
        method=getattr(policy, "name", "policy"),
        evidence_count=len(env.evidence_packs),
    )


def random_policy_factory(rng: np.random.Generator):
    def policy(obs, env):
        return rng.uniform(-1.0, 1.0, size=7).astype(np.float32)

    policy.name = "random"
    return policy


def hillclimb_policy_factory(rng: np.random.Generator):
    """Greedy random search: try a step; keep if reward positive via one-step look."""

    best_action = np.zeros(7, dtype=np.float32)

    def policy(obs, env):
        nonlocal best_action
        candidates = [rng.uniform(-1.0, 1.0, size=7) for _ in range(8)]
        candidates.append(best_action)
        # pick action with best one-step reward estimate using env.state clone path
        from .monitors import monitor_action
        from .env import _reward

        best_a = candidates[0]
        best_score = -1e9
        for a in candidates:
            d = monitor_action(env.state, a)
            if not d.allow or d.projected is None:
                score = -1.0
            else:
                score = _reward(d.projected, env.parent_ct, env.parent_vol)
            if score > best_score:
                best_score = score
                best_a = a
        best_action = np.asarray(best_a, dtype=np.float32)
        return best_action

    policy.name = "hillclimb"
    return policy


def run_search(
    parents: list[HullState],
    steps: int = 40,
    seed: int = 0,
    evidence_root: Path | None = None,
) -> list[dict[str, Any]]:
    rng = np.random.default_rng(seed)
    results: list[dict[str, Any]] = []
    for i, parent in enumerate(parents):
        parent_ct = estimate_resistance(parent).Ct
        ed = None if evidence_root is None else evidence_root / f"parent_{i:02d}"
        env = DesignSearchEnv(parent=parent, max_steps=steps, seed=seed + i, evidence_dir=str(ed) if ed else None)
        for factory in (random_policy_factory, hillclimb_policy_factory):
            policy = factory(rng)
            child = _run_episode(env, policy, steps)
            row = child.to_dict()
            row["delta_ct_vs_parent"] = parent_ct - child.ct
            row["parent_ct"] = parent_ct
            row["parent_index"] = i
            row["improved"] = child.ct < parent_ct and estimate_resistance(child.hull).Ct > 0
            results.append(row)
        # Optional BoTorch
        try:
            child_bo = _botorch_child(parent, steps=min(steps, 25), seed=seed + 100 + i)
            if child_bo is not None:
                results.append(child_bo)
        except Exception as exc:  # noqa: BLE001
            results.append(
                {
                    "method": "botorch",
                    "skipped": True,
                    "reason": str(exc),
                    "parent_index": i,
                }
            )
    return results


def _botorch_child(parent: HullState, steps: int, seed: int) -> dict[str, Any] | None:
    try:
        import torch
        from botorch.acquisition import ExpectedImprovement
        from botorch.fit import fit_gpytorch_mll
        from botorch.models import SingleTaskGP
        from botorch.optim import optimize_acqf
        from gpytorch.mlls import ExactMarginalLogLikelihood
    except ImportError:
        return {
            "method": "botorch",
            "skipped": True,
            "reason": "botorch/torch not installed",
            "parent_index": None,
        }

    from .monitors import monitor_action
    from .env import _reward

    torch.manual_seed(seed)
    parent_ct = estimate_resistance(parent).Ct
    parent_vol = parent.volume()
    train_x = []
    train_y = []
    # Latin-ish random initial
    rng = np.random.default_rng(seed)
    for _ in range(max(5, steps // 5)):
        a = rng.uniform(-1, 1, size=7)
        d = monitor_action(parent, a)
        if d.allow and d.projected is not None:
            y = _reward(d.projected, parent_ct, parent_vol)
            train_x.append(a)
            train_y.append([y])
    if len(train_x) < 3:
        return {"method": "botorch", "skipped": True, "reason": "insufficient feasible samples"}

    best_hull = parent
    best_y = -1e9
    X = torch.tensor(train_x, dtype=torch.double)
    Y = torch.tensor(train_y, dtype=torch.double)
    for _ in range(steps):
        model = SingleTaskGP(X, Y)
        mll = ExactMarginalLogLikelihood(model.likelihood, model)
        fit_gpytorch_mll(mll)
        ei = ExpectedImprovement(model, best_f=Y.max())
        cand, _ = optimize_acqf(
            ei,
            bounds=torch.tensor([[-1.0] * 7, [1.0] * 7], dtype=torch.double),
            q=1,
            num_restarts=4,
            raw_samples=32,
        )
        a = cand.detach().numpy().reshape(-1)
        d = monitor_action(parent, a)
        if not d.allow or d.projected is None:
            y = -1.0
            hull = parent
        else:
            y = _reward(d.projected, parent_ct, parent_vol)
            hull = d.projected
            if y > best_y:
                best_y = y
                best_hull = hull
        X = torch.cat([X, cand.detach()], dim=0)
        Y = torch.cat([Y, torch.tensor([[y]], dtype=torch.double)], dim=0)

    ct = estimate_resistance(best_hull).Ct
    return {
        "method": "botorch",
        "ct": ct,
        "reward_sum": best_y,
        "delta_ct_vs_parent": parent_ct - ct,
        "parent_ct": parent_ct,
        "improved": ct < parent_ct,
        "hull": best_hull.to_dict(),
        "evidence_count": 0,
    }
