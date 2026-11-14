"""Yard applications of ``conformal.py`` (labelled; read-only consumers of other modules).

1. ``lf_hf_conformal`` — cheap L1 total resistance (what the reward sees) vs the
   L1.5 composite (L1 viscous + Michell wave, ``multi_froude`` with
   ``wave_oracle="michell"``) on hulls drawn i.i.d. from a stated sampler. This
   *is* an exchangeable setting, so the split-conformal interval tells a
   multi-fidelity search how far the L1 number can be from the L1.5 number for
   a new hull from the same sampler. Model-vs-model: it calibrates surrogate
   disagreement, not physical truth.
2. ``tank_conformal`` — oracle C_T vs measured towing-tank C_T from
   ``validation.py`` (public KCS / JBC / KVLCC2 / DTMB 5415 reference). Physical
   reference, but only ~11 points on 4 hulls, which are not exchangeable;
   leave-one-hull-out coverage is reported next to the pooled interval.
"""

from __future__ import annotations

import dataclasses
from typing import Any

import numpy as np

from .conformal import SplitConformal, group_cv, random_split_coverage
from .hull import HullState, evaluate_l0

SAMPLER = {"L": (60.0, 250.0), "L_B": (5.0, 8.0), "T_B": (0.3, 0.45), "Cb": (0.5, 0.85),
           "Fn": (0.15, 0.28), "lcb_frac": (-0.03, 0.03)}


def sample_hulls(n: int, seed: int = 0) -> list[HullState]:
    """i.i.d. L0-feasible hulls from the uniform box ``SAMPLER`` (rejection on L0)."""
    rng = np.random.default_rng(seed)
    out: list[HullState] = []
    while len(out) < n:
        L = rng.uniform(*SAMPLER["L"])
        B = L / rng.uniform(*SAMPLER["L_B"])
        h = HullState(L=L, B=B, T=B * rng.uniform(*SAMPLER["T_B"]), Cb=rng.uniform(*SAMPLER["Cb"]),
                      lcb_frac=rng.uniform(*SAMPLER["lcb_frac"]), Fn=rng.uniform(*SAMPLER["Fn"]))
        if evaluate_l0(h).feasible:
            out.append(h)
    return out


def lf_hf_pairs(hulls: list[HullState]) -> tuple[np.ndarray, np.ndarray, str]:
    from .multi_froude import evaluate_point

    lf, hf = [], []
    fid = None
    for h in hulls:
        p_l1 = evaluate_point(h, h.Fn, wave_oracle="l1")
        p_hf = evaluate_point(h, h.Fn, wave_oracle="michell")
        if not (p_l1.accepted and p_hf.accepted):
            continue
        lf.append(p_l1.total)
        hf.append(p_hf.total)
    from .resistance_l1 import estimate_resistance

    fid = str(estimate_resistance(hulls[0]).fidelity) if hulls else "n/a"
    return np.asarray(lf), np.asarray(hf), fid


def lf_hf_conformal(n: int = 200, *, alpha: float = 0.1, seed: int = 0) -> dict[str, Any]:
    hulls = sample_hulls(n, seed)
    lf, hf, fid = lf_hf_pairs(hulls)
    m = len(lf)
    half = m // 2
    cp = SplitConformal(alpha, "rel").fit(lf[:half], hf[:half])
    test = cp.evaluate(lf[half:], hf[half:])
    rec = cp.to_evidence(
        surrogate=f"L1 Ct ({fid})", reference="L1 viscous + Michell L1.5 wave Ct (multi_froude, S basis)",
        test=test, extra={"sampler": SAMPLER, "seed": seed, "n_pairs": m,
                          "random_splits": random_split_coverage(lf, hf, alpha=alpha, score="rel"),
                          "scope": "model-vs-model surrogate disagreement, not physical truth"})
    return rec


def tank_conformal(oracle: str = "simplified_py", *, alpha: float = 0.2) -> dict[str, Any]:
    from .validation import validate

    rep = validate(oracles=(oracle,))
    rows = [r for r in rep["rows"] if r["oracles"][oracle].get("available")]
    if not rows:
        return {"type": "conformal_calibration", "oracle": oracle, "available": False,
                "reason": "oracle unavailable on this machine"}
    pred = np.array([r["oracles"][oracle]["CT"] for r in rows])
    ref = np.array([r["CT_measured"] for r in rows])
    hulls = [r["hull"] for r in rows]
    cp = SplitConformal(alpha, "rel").fit(pred, ref)
    return cp.to_evidence(
        surrogate=f"{oracle} model-scale C_T", reference="measured towing-tank C_T (validation.py)",
        extra={"available": True, "hulls": sorted(set(hulls)), "n_points": len(rows),
               "leave_one_hull_out": group_cv(pred, ref, hulls, alpha=alpha, score="rel"),
               "scope": ("pooled q_hat is in-sample over 4 non-exchangeable hulls; use the "
                         "leave-one-hull-out coverage as the honest out-of-hull estimate")})


def main(argv: list[str] | None = None) -> int:
    import argparse
    import json

    ap = argparse.ArgumentParser(prog="yard_sea_v0.conformal_yard")
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--alpha", type=float, default=0.1)
    ap.add_argument("--tank-oracle", default="simplified_py")
    a = ap.parse_args(argv)
    lf = lf_hf_conformal(a.n, alpha=a.alpha)
    tk = tank_conformal(a.tank_oracle)
    print(json.dumps({"lf_hf": {k: lf[k] for k in ("q_hat", "n_cal", "test")},
                      "lf_hf_random_splits": lf["random_splits"],
                      "tank": {k: tk.get(k) for k in ("q_hat", "n_cal", "available")},
                      "tank_loho": (tk.get("leave_one_hull_out") or {}).get("pooled_coverage")},
                     indent=1, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
