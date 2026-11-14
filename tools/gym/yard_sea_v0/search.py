"""Search baselines: random, hill-climb, optional BoTorch."""

from __future__ import annotations

import json
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from . import __version__
from .env import DesignSearchEnv
from .hull import HullState
from .provenance import OptimizerRecord
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


def botorch_available() -> bool:
    """True when torch + botorch + gpytorch import cleanly."""
    try:
        import botorch  # noqa: F401
        import gpytorch  # noqa: F401
        import torch  # noqa: F401
    except ImportError:
        return False
    return True


def _run_episode(
    env: DesignSearchEnv, policy, steps: int, options: dict[str, Any] | None = None
) -> ChildResult:
    obs, info = env.reset(options=options)
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
        from .monitors import monitor_action

        best_a = candidates[0]
        best_score = -1e9
        for a in candidates:
            d = monitor_action(env.state, a)
            if not d.allow or d.projected is None:
                score = -1.0
            else:
                score = env.candidate_reward(d.projected)
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
    *,
    use_botorch: bool = False,
    reward_mode: str = "single_fn",
    wave_oracle: str = "l1",
) -> list[dict[str, Any]]:
    """Run random + hill-climb (and optional BoTorch) per parent.

    BoTorch is opt-in via ``use_botorch=True`` (CLI ``--botorch``). When
    enabled but packages are missing, a skipped row is recorded — never raises.
    """
    rng = np.random.default_rng(seed)
    results: list[dict[str, Any]] = []
    for i, parent in enumerate(parents):
        parent_ct = estimate_resistance(parent).Ct
        ed = None if evidence_root is None else evidence_root / f"parent_{i:02d}"
        env = DesignSearchEnv(
            parent=parent,
            max_steps=steps,
            seed=seed + i,
            evidence_dir=str(ed) if ed else None,
            reward_mode=reward_mode,
            wave_oracle=wave_oracle,
        )
        for factory in (random_policy_factory, hillclimb_policy_factory):
            policy = factory(rng)
            name = getattr(policy, "name", "policy")
            opt = OptimizerRecord(
                implementation=f"yard_sea_v0.search.{name}",
                version=__version__,
                settings={"candidates_per_step": 8} if name == "hillclimb" else {"dist": "uniform[-1,1]^7"},
                max_evals=int(steps),
            ).start()
            # Same episode_index for every policy => shared env randomness (CRN).
            child = _run_episode(env, policy, steps, options={"episode_index": 0, "optimizer": opt})
            row = child.to_dict()
            row["optimizer"] = opt.to_dict()
            row["seeds"] = dict(env.seeds)
            row["episode_id"] = env.episode_id
            row["delta_ct_vs_parent"] = parent_ct - child.ct
            row["parent_ct"] = parent_ct
            row["parent_index"] = i
            # Measure-then-claim: "improved" is the env's fresh re-measurement verdict.
            verdict = env.claim_done({"Ct": child.ct})
            row["improved"] = bool(verdict["accepted"])
            row["claim"] = {
                "accepted": verdict["accepted"],
                "reasons": verdict["reasons"],
                "measured_ct": verdict["measured"]["Ct"],
            }
            results.append(row)
        if use_botorch:
            try:
                # Small budgets still get a few BO iterations after init design.
                bo_steps = max(3, min(int(steps), 25))
                child_bo = _botorch_child(parent, steps=bo_steps, seed=seed + 100 + i)
                if child_bo is not None:
                    child_bo["parent_index"] = i
                    if "parent_ct" not in child_bo:
                        child_bo["parent_ct"] = parent_ct
                    results.append(child_bo)
            except Exception as exc:  # noqa: BLE001
                results.append(
                    {
                        "method": "botorch",
                        "skipped": True,
                        "reason": str(exc),
                        "parent_index": i,
                        "parent_ct": parent_ct,
                    }
                )
    return results


def _botorch_child(parent: HullState, steps: int, seed: int) -> dict[str, Any] | None:
    """Bayesian optimization over 7-D relative morph actions (L0-gated reward)."""
    try:
        import torch
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

    try:
        from botorch.acquisition import LogExpectedImprovement as _Acq
    except ImportError:  # pragma: no cover — older botorch
        from botorch.acquisition import ExpectedImprovement as _Acq

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
            "method": "botorch",
            "skipped": True,
            "reason": "insufficient feasible samples",
            "parent_ct": parent_ct,
        }

    X = torch.tensor(np.asarray(train_x, dtype=np.float64), dtype=torch.double)
    Y = torch.tensor(np.asarray(train_y, dtype=np.float64), dtype=torch.double)
    # Standardize outcomes for GP numerical stability on short budgets.
    y_mean = Y.mean()
    y_std = Y.std().clamp_min(1e-6)
    Yn = (Y - y_mean) / y_std

    bounds = torch.tensor([[-1.0] * 7, [1.0] * 7], dtype=torch.double)
    n_bo = max(1, int(steps))
    # Keep restarts cheap so small budgets finish quickly.
    n_restarts = 2 if n_bo <= 5 else 4
    raw_samples = 16 if n_bo <= 5 else 32

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        for _ in range(n_bo):
            model = SingleTaskGP(X, Yn)
            mll = ExactMarginalLogLikelihood(model.likelihood, model)
            fit_gpytorch_mll(mll)
            acq = _Acq(model, best_f=Yn.max())
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
            y_t = torch.tensor([[y]], dtype=torch.double)
            Y = torch.cat([Y, y_t], dim=0)
            Yn = (Y - y_mean) / y_std

    ct = float(best_ct)
    return {
        "method": "botorch",
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
    }


def run_env45_search(
    n_samples: int = 3,
    steps: int = 20,
    seed: int = 0,
    out_dir: Path | None = None,
) -> list[dict[str, Any]]:
    """Random 45-D episodes on DesignSearchEnv45 sample seeds."""
    from .env45 import ACTION_DIM, DesignSearchEnv45
    from .shipd import load_sample_vectors

    rng = np.random.default_rng(seed)
    samples = load_sample_vectors()
    n = min(int(n_samples), len(samples))
    rows: list[dict[str, Any]] = []
    if out_dir is not None:
        Path(out_dir).mkdir(parents=True, exist_ok=True)
    for i in range(n):
        env = DesignSearchEnv45(
            sample_index=i,
            max_steps=steps,
            seed=seed + i,
            evidence_dir=str(Path(out_dir) / f"sample_{i:02d}") if out_dir else None,
        )
        obs, info = env.reset()
        parent_ct = float(info.get("parent_ct") or estimate_resistance(env.state).Ct)
        n_rej = 0
        n_shipd = 0
        total_r = 0.0
        for _ in range(steps):
            a = rng.uniform(-1.0, 1.0, size=ACTION_DIM).astype(np.float32)
            obs, reward, term, trunc, step_info = env.step(a)
            total_r += float(reward)
            if step_info.get("rejected"):
                n_rej += 1
            if step_info.get("shipd_infeasible"):
                n_shipd += 1
            if term or trunc:
                break
        ct = estimate_resistance(env.state).Ct
        row = {
            "method": "env45_random",
            "sample_index": i,
            "action_dim": ACTION_DIM,
            "ct": ct,
            "parent_ct": parent_ct,
            "delta_ct_vs_parent": parent_ct - ct,
            "reward_sum": total_r,
            "n_rejected": n_rej,
            "n_shipd_infeasible": n_shipd,
            "all_rejected": n_rej == steps,
            "improved": ct < parent_ct,
            "hull": env.state.to_dict(),
            "shipd_vector": list(env.shipd_vector.values),
            "evidence_count": len(env.evidence_packs),
        }
        rows.append(row)
        if out_dir is not None:
            (Path(out_dir) / f"env45_sample_{i:02d}.json").write_text(
                json.dumps(row, indent=2, sort_keys=True)
            )
    if out_dir is not None:
        (Path(out_dir) / "env45_summary.json").write_text(
            json.dumps({"n": len(rows), "rows": rows}, indent=2, sort_keys=True)
        )
    return rows
