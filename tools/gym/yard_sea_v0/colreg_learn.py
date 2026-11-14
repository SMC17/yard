"""Small learned COLREG policies trained on the suite (``colreg_learn_v0``).

Two learners, both honest baselines rather than tuned agents:

* **CEM** (numpy only): a 20→8→1 tanh MLP mapping hand-built features of the two
  most dangerous perceived targets to a heading alteration in ±90° from the
  route, trained by the cross-entropy method on an episode cost evaluated on
  ground truth (collision, passing-distance shortfall, own-ship rule checks,
  cross-track, return to route).
* **PPO** (optional; ``stable-baselines3`` + ``torch``): same features and action
  through ``ColregGymEnv``, a gymnasium wrapper over ``simulate_iter`` with a
  decision every ``decision_s`` and dense truth-based shaping at training time.

Training scenarios use generator seeds ≥ 1000; the evaluation table uses the
standard seeds 0–9, so scenarios are disjoint (same generator distribution).
The policy sees only perceived (possibly faulted) data. Features look at two
targets, so dense multi-ship traffic is out of scope. No claim of COLREG
compliance, of safety, or that these agents are good — they exist so the
Simplex wrapper can be evaluated around a *real* learned controller instead of
the stand-ins.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any, Sequence

import numpy as np

from .colreg_stub import Thresholds, Vessel, classify, cpa_tcpa
from .colreg_suite import KINDS, VARIANTS, SuiteConventions, generate, simulate, simulate_iter

LABEL = "colreg_learn_v0"
N_TGT = 2
PER_T = 9
N_FEAT = 2 + N_TGT * PER_T
HIDDEN = 8
N_PARAMS = N_FEAT * HIDDEN + HIDDEN + HIDDEN + 1
MAX_ALT_DEG = 90.0
TRAIN_SEEDS = tuple(range(1000, 1004))
TRAIN_VARIANTS = ("nominal", "gnss_degraded", "comms_loss")


def features(own: Vessel, targets: Sequence[Vessel], route: float, th: Thresholds = Thresholds()) -> np.ndarray:
    """Own-route-frame features of the two most dangerous perceived targets (zeros if absent)."""
    a = math.radians(own.course_deg - route)
    f = [math.sin(a), math.cos(a)]
    c, s_ = math.cos(math.radians(own.course_deg)), math.sin(math.radians(own.course_deg))
    rows = []
    for tg in targets:
        d, t = cpa_tcpa(own, tg)
        cl = classify(own, tg, th)
        dx, dy = tg.x - own.x, tg.y - own.y
        # body frame: x = starboard, y = ahead
        bx, by = dx * c - dy * s_, dx * s_ + dy * c
        tv = math.radians(tg.course_deg)
        vx, vy = tg.speed * math.sin(tv) - own.speed * s_, tg.speed * math.cos(tv) - own.speed * c
        bvx, bvy = vx * c - vy * s_, vx * s_ + vy * c
        danger = (d if 0 < t < 1500 else 1e4) + 1e-3 * math.hypot(dx, dy)
        rows.append((danger, [1.0, bx / 5000, by / 5000, bvx / 10, bvy / 10,
                              min(d, 4000) / 2000, float(np.clip(t, -300, 1500)) / 1500,
                              float(cl["risk_of_collision"] and cl["role"] == "give_way"),
                              float(cl["risk_of_collision"] and cl["role"] == "stand_on")]))
    rows.sort(key=lambda r: r[0])
    for i in range(N_TGT):
        f += rows[i][1] if i < len(rows) else [0.0] * PER_T
    return np.asarray(f, dtype=np.float64)


@dataclass
class MLPPolicy:
    params: np.ndarray
    name: str = "learned_mlp"
    th: Thresholds = field(default_factory=Thresholds)
    log: list = field(default_factory=list)

    def act(self, x: np.ndarray) -> float:
        p = np.asarray(self.params, dtype=float)
        W1 = p[: N_FEAT * HIDDEN].reshape(HIDDEN, N_FEAT)
        b1 = p[N_FEAT * HIDDEN: N_FEAT * HIDDEN + HIDDEN]
        W2 = p[N_FEAT * HIDDEN + HIDDEN: N_FEAT * HIDDEN + 2 * HIDDEN]
        b2 = p[-1]
        return float(np.tanh(W2 @ np.tanh(W1 @ x + b1) + b2))

    def __call__(self, t: float, own: Vessel, targets: list[Vessel], route: float) -> float:
        return (route + MAX_ALT_DEG * self.act(features(own, targets, route, self.th))) % 360.0


def episode_cost(r: dict[str, Any], th: Thresholds = Thresholds()) -> float:
    cost = 100.0 * r["collision"]
    cost += 20.0 * max(0.0, 0.8 * th.dcpa_min_m - r["min_range_m"]) / th.dcpa_min_m
    cost += 5.0 * (not r["rule_consistent"])
    cost += 2.0 * min(r["max_cross_track_m"], 10000.0) / 5000.0
    cost += 1.0 * (not r["returned_to_route"])
    return float(cost)


def train_scenarios(seeds: Sequence[int] = TRAIN_SEEDS, variants: Sequence[str] = TRAIN_VARIANTS):
    return [generate(k, s, v) for k in KINDS for v in variants for s in seeds]


def _eval_params(args: tuple[np.ndarray, list]) -> float:
    params, scs = args
    return float(np.mean([episode_cost(simulate(sc, MLPPolicy(params))) for sc in scs]))


def cem_train(scenarios: list | None = None, *, iters: int = 20, pop: int = 48, elite_frac: float = 0.15,
              init_std: float = 0.5, seed: int = 0, n_jobs: int = 1, verbose: bool = False) -> dict[str, Any]:
    scs = scenarios if scenarios is not None else train_scenarios()
    rng = np.random.default_rng(seed)
    mu, sd = np.zeros(N_PARAMS), np.full(N_PARAMS, init_std)
    n_el = max(2, int(round(elite_frac * pop)))
    hist, best = [], (math.inf, mu.copy())
    pool = None
    if n_jobs > 1:
        import multiprocessing as mp

        pool = mp.get_context("fork").Pool(n_jobs)
    try:
        for it in range(iters):
            cand = mu + sd * rng.standard_normal((pop, N_PARAMS))
            cand[0] = mu  # keep the current mean in the population
            jobs = [(c, scs) for c in cand]
            costs = np.array(pool.map(_eval_params, jobs) if pool else [_eval_params(j) for j in jobs])
            order = np.argsort(costs)
            el = cand[order[:n_el]]
            mu, sd = el.mean(0), el.std(0) + 0.02
            if costs[order[0]] < best[0]:
                best = (float(costs[order[0]]), cand[order[0]].copy())
            hist.append({"iter": it, "best": float(costs[order[0]]), "mean_elite": float(costs[order[:n_el]].mean()),
                         "median": float(np.median(costs))})
            if verbose:
                print(hist[-1], flush=True)
    finally:
        if pool:
            pool.close()
    return {"label": LABEL, "method": "cem", "params": best[1].tolist(), "train_cost": best[0], "history": hist,
            "n_train_scenarios": len(scs), "iters": iters, "pop": pop, "seed": seed}


# ------------------------------------------------------------------ gymnasium wrapper for PPO
try:
    import gymnasium as gym

    _HAS_GYM = True
except Exception:  # pragma: no cover
    _HAS_GYM = False


class ColregGymEnv(gym.Env if _HAS_GYM else object):  # type: ignore[misc]
    """One scenario per episode, sampled from ``scenarios``; action ∈ [−1, 1] → ±90° alteration."""

    metadata: dict = {}

    def __init__(self, scenarios: list | None = None, *, decision_s: float = 30.0, seed: int = 0,
                 conv: SuiteConventions = SuiteConventions(), th: Thresholds = Thresholds()) -> None:
        self.scs = scenarios if scenarios is not None else train_scenarios()
        self.decision_steps = max(1, int(round(decision_s / conv.dt_s)))
        self.conv, self.th = conv, th
        self._rng = np.random.default_rng(seed)
        if _HAS_GYM:
            self.observation_space = gym.spaces.Box(-10.0, 10.0, (N_FEAT,), np.float32)
            self.action_space = gym.spaces.Box(-1.0, 1.0, (1,), np.float32)
        self.result: dict[str, Any] | None = None

    def _obs(self) -> np.ndarray:
        t, own, tg, route, _ = self._cur
        return features(own, tg, route, self.th).astype(np.float32)

    def reset(self, *, seed: int | None = None, options: dict | None = None):
        if seed is not None:
            self._rng = np.random.default_rng(seed)
        sc = self.scs[int(self._rng.integers(len(self.scs)))]
        self._gen = simulate_iter(sc, th=self.th, conv=self.conv, expose_truth=True)
        self._cur = next(self._gen)
        self.result = None
        return self._obs(), {"scenario": sc.id}

    def step(self, action):
        a = float(np.clip(np.asarray(action).reshape(-1)[0], -1.0, 1.0))
        reward = -0.002 * abs(a)
        done = False
        for _ in range(self.decision_steps):
            t, own, tg, route, (own_true, tg_true) = self._cur
            rng_min = min((math.hypot(o.x - own_true.x, o.y - own_true.y) for o in tg_true), default=math.inf)
            reward -= 0.05 * max(0.0, 1.0 - rng_min / self.th.dcpa_min_m)
            reward -= 0.0005 * abs(own_true.x) / 1000.0
            try:
                self._cur = self._gen.send(route + MAX_ALT_DEG * a)
            except StopIteration as stop:
                self.result = stop.value
                done = True
                break
        if done:
            reward -= episode_cost(self.result, self.th) / 10.0
            return np.zeros(N_FEAT, np.float32), reward, True, False, {"result": self.result}
        return self._obs(), reward, False, False, {}


@dataclass
class SB3Policy:
    """Adapter: a trained stable-baselines3 model as a suite policy (deterministic)."""

    model: Any
    name: str = "learned_ppo"
    th: Thresholds = field(default_factory=Thresholds)
    log: list = field(default_factory=list)

    def __call__(self, t: float, own: Vessel, targets: list[Vessel], route: float) -> float:
        a, _ = self.model.predict(features(own, targets, route, self.th).astype(np.float32), deterministic=True)
        return (route + MAX_ALT_DEG * float(np.clip(np.asarray(a).reshape(-1)[0], -1, 1))) % 360.0


def ppo_train(total_timesteps: int = 1_000_000, out: str | None = None, *, n_envs: int = 8, seed: int = 0):
    """Optional PPO (stable-baselines3) on ``ColregGymEnv``; returns the model."""
    import torch
    from stable_baselines3 import PPO
    from stable_baselines3.common.env_util import make_vec_env
    from stable_baselines3.common.vec_env import DummyVecEnv, SubprocVecEnv

    torch.set_num_threads(1)
    kw = ({"vec_env_cls": SubprocVecEnv, "vec_env_kwargs": {"start_method": "fork"}} if n_envs > 1
          else {"vec_env_cls": DummyVecEnv})
    venv = make_vec_env(lambda: ColregGymEnv(), n_envs=n_envs, seed=seed, **kw)
    model = PPO("MlpPolicy", venv, n_steps=256, batch_size=256, n_epochs=10, gamma=0.995,
                learning_rate=3e-4, seed=seed, policy_kwargs={"net_arch": [32, 32]}, verbose=0)
    model.learn(total_timesteps=total_timesteps)
    venv.close()
    if out:
        model.save(out)
    return model


SHIPPED_CEM = __import__("pathlib").Path(__file__).resolve().parents[1] / "policies" / "colreg_cem_v0.json"


def load_cem(path=None) -> MLPPolicy:
    import json

    rec = json.loads(__import__("pathlib").Path(path or SHIPPED_CEM).read_text())
    return MLPPolicy(np.asarray(rec["params"], dtype=float))


def main(argv: Sequence[str] | None = None) -> int:
    """``python -m yard_sea_v0.colreg_learn cem --iters 25 --out policies/x.json`` or ``ppo --steps 1000000``."""
    import argparse
    import json
    from pathlib import Path

    ap = argparse.ArgumentParser(prog="yard_sea_v0.colreg_learn")
    ap.add_argument("method", choices=("cem", "ppo", "eval-shipped"))
    ap.add_argument("--iters", type=int, default=25)
    ap.add_argument("--pop", type=int, default=48)
    ap.add_argument("--steps", type=int, default=1_000_000)
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--out", type=Path, default=None)
    a = ap.parse_args(argv)
    if a.method == "cem":
        res = cem_train(iters=a.iters, pop=a.pop, n_jobs=a.jobs, verbose=True)
        if a.out:
            a.out.write_text(json.dumps(res, indent=1))
        pol = lambda: MLPPolicy(np.asarray(res["params"]))  # noqa: E731
    elif a.method == "ppo":
        from stable_baselines3 import PPO

        ppo_train(a.steps, str(a.out) if a.out else None, n_envs=a.jobs)
        path = str(a.out) if a.out else None
        if path is None:
            return 0
        pol = lambda: SB3Policy(PPO.load(path, device="cpu"))  # noqa: E731
    else:
        pol = load_cem
    print(json.dumps(evaluate(pol), indent=1))
    return 0



def evaluate(policy_factory, *, seeds: Sequence[int] = range(10), variants: Sequence[str] = VARIANTS,
             reciprocal: bool = False) -> dict[str, Any]:
    """Standard 240-run table for a learned policy: bare, + CPA RTA, + CPA RTA with GNSS integrity."""
    from .colreg_suite import run_suite
    from .runtime_assurance import ColregRTA, GnssIntegrityMonitor

    cfgs = {"bare": None, "rta": ColregRTA,
            "rta_gnss": lambda: ColregRTA(gnss_monitor=GnssIntegrityMonitor())}
    out = {}
    for name, wf in cfgs.items():
        r = run_suite(seeds=tuple(seeds), variants=variants, policy_factory=policy_factory,
                      wrapper_factory=wf, reciprocal=reciprocal)
        rs = r["results"]
        out[name] = {
            "n": len(rs),
            "collision_rate": float(np.mean([x["collision"] for x in rs])),
            "passing_ok_rate": float(np.mean([x["passing_ok"] for x in rs])),
            "rule_consistent_rate": float(np.mean([x["rule_consistent"] for x in rs])),
            "mean_cost": float(np.mean([episode_cost(x) for x in rs])),
            "fallback_fraction_mean": (float(np.mean([x["runtime_assurance"]["fallback_fraction"] for x in rs]))
                                       if wf else None),
            "by_variant_collisions": {v: int(sum(x["collision"] for x in rs if x["scenario"]["variant"] == v))
                                      for v in variants},
        }
    return out


if __name__ == "__main__":
    raise SystemExit(main())
