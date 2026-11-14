"""Split-conformal calibration of surrogate-vs-reference residuals (``conformal_split_v0``).

Given surrogate predictions ``p_i`` and reference values ``y_i`` on a
calibration set, the nonconformity score is ``|y - p|`` (``score="abs"``) or
``|y - p| / |p|`` (``score="rel"``). With ``n`` calibration scores the
interval for a new prediction is ``p ± q̂`` (abs) or ``p·(1 ± q̂)`` (rel), where
``q̂`` is the ``⌈(n+1)(1-α)⌉``-th smallest score. If that rank exceeds ``n`` the
honest answer is an infinite interval (reported as ``q_hat = inf``).

Assumptions — recorded verbatim in every evidence record:

* Calibration and test pairs are **exchangeable** (e.g. i.i.d. from the same
  sampler). Then coverage ≥ 1-α holds **marginally** (on average over draws),
  not conditionally on any particular design, operating condition or region.
* It says nothing under distribution shift (new design families, new
  operating conditions).
  ``group_cv`` reports leave-one-group-out coverage so the effect of shift is
  measured rather than assumed away.
* Reference values are taken as ground truth; their own uncertainty is not
  propagated.

Pure numpy, domain-neutral. **Canonical copy**: SMC17/yard
``tools/gym/yard_sea_v0/conformal.py``. SMC17/strip vendors it byte-for-byte as
``tools/gym/strip_uas_v0/conformal.py``. ``tests/test_conformal_sync.py`` in both
repos pins the file's SHA-256 (and compares against a sibling checkout when one
is found) — change both files and both pins together.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any, Sequence

import numpy as np

LABEL = "conformal_split_v0"
ASSUMPTIONS = (
    "Split conformal: marginal coverage >= 1-alpha only if calibration and test pairs are "
    "exchangeable; not conditional on design/condition; no guarantee under distribution shift; "
    "reference treated as exact."
)
SCORES = ("abs", "rel")


def conformal_quantile(scores: Sequence[float], alpha: float) -> float:
    s = np.sort(np.asarray(scores, dtype=float))
    n = len(s)
    if not 0.0 < alpha < 1.0:
        raise ValueError("alpha must be in (0, 1)")
    k = math.ceil((n + 1) * (1.0 - alpha))
    return float("inf") if k > n or n == 0 else float(s[k - 1])


def min_calibration_size(alpha: float) -> int:
    """Smallest n with a finite split-conformal quantile at level 1-alpha."""
    return math.ceil(1.0 / alpha) - 1


def _scores(pred: np.ndarray, ref: np.ndarray, score: str) -> np.ndarray:
    r = np.abs(ref - pred)
    if score == "abs":
        return r
    if score == "rel":
        return r / np.maximum(np.abs(pred), 1e-300)
    raise ValueError(f"score must be one of {SCORES}")


@dataclass
class SplitConformal:
    alpha: float = 0.1
    score: str = "rel"
    q_hat: float | None = None
    n_cal: int = 0
    cal_scores: list[float] = field(default_factory=list)

    def fit(self, pred: Sequence[float], ref: Sequence[float]) -> "SplitConformal":
        p, y = np.asarray(pred, dtype=float), np.asarray(ref, dtype=float)
        if p.shape != y.shape:
            raise ValueError("pred and ref must have the same shape")
        s = _scores(p, y, self.score)
        self.cal_scores = s.tolist()
        self.n_cal = int(len(s))
        self.q_hat = conformal_quantile(s, self.alpha)
        return self

    def interval(self, pred: Sequence[float] | float) -> tuple[np.ndarray, np.ndarray]:
        if self.q_hat is None:
            raise RuntimeError("fit first")
        p = np.asarray(pred, dtype=float)
        if self.score == "abs":
            return p - self.q_hat, p + self.q_hat
        w = np.abs(p) * self.q_hat
        return p - w, p + w

    def evaluate(self, pred: Sequence[float], ref: Sequence[float]) -> dict[str, Any]:
        lo, hi = self.interval(pred)
        y = np.asarray(ref, dtype=float)
        cov = (y >= lo) & (y <= hi)
        width = hi - lo
        return {"n_test": int(len(y)), "coverage": float(cov.mean()) if len(y) else None,
                "mean_width": float(np.mean(width)) if len(y) else None,
                "target_coverage": 1.0 - self.alpha}

    def to_evidence(self, *, surrogate: str, reference: str, test: dict[str, Any] | None = None,
                    extra: dict[str, Any] | None = None) -> dict[str, Any]:
        rec = {"type": "conformal_calibration", "label": LABEL, "surrogate": surrogate,
               "reference": reference, "alpha": self.alpha, "score": self.score,
               "n_cal": self.n_cal, "q_hat": self.q_hat,
               "finite": self.q_hat is not None and math.isfinite(self.q_hat),
               "min_n_for_finite": min_calibration_size(self.alpha),
               "assumptions": ASSUMPTIONS}
        if test is not None:
            rec["test"] = test
        if extra:
            rec.update(extra)
        return rec


def random_split_coverage(pred: Sequence[float], ref: Sequence[float], *, alpha: float = 0.1,
                          score: str = "rel", cal_frac: float = 0.5, n_splits: int = 200,
                          seed: int = 0) -> dict[str, Any]:
    """Empirical check of the guarantee: mean test coverage over random cal/test splits."""
    p, y = np.asarray(pred, dtype=float), np.asarray(ref, dtype=float)
    rng = np.random.default_rng(seed)
    n = len(p)
    n_cal = max(1, int(round(cal_frac * n)))
    covs, widths = [], []
    for _ in range(n_splits):
        idx = rng.permutation(n)
        c, t = idx[:n_cal], idx[n_cal:]
        cp = SplitConformal(alpha, score).fit(p[c], y[c])
        ev = cp.evaluate(p[t], y[t])
        covs.append(ev["coverage"])
        widths.append(ev["mean_width"])
    return {"alpha": alpha, "score": score, "n": n, "n_cal": n_cal, "n_splits": n_splits,
            "mean_coverage": float(np.mean(covs)), "std_coverage": float(np.std(covs)),
            "mean_width": float(np.mean(widths)), "target_coverage": 1.0 - alpha}


def group_cv(pred: Sequence[float], ref: Sequence[float], groups: Sequence[Any], *,
             alpha: float = 0.1, score: str = "rel") -> dict[str, Any]:
    """Leave-one-group-out: calibrate on the other groups, test on the held-out group.

    Exposes what happens when the exchangeability assumption fails across groups
    (e.g. calibrating on some designs or conditions and predicting a new one).
    """
    p, y = np.asarray(pred, dtype=float), np.asarray(ref, dtype=float)
    g = np.asarray(groups, dtype=object)
    per: dict[str, Any] = {}
    hits = 0
    total = 0
    for grp in sorted(set(g.tolist()), key=str):
        m = g == grp
        cp = SplitConformal(alpha, score).fit(p[~m], y[~m])
        ev = cp.evaluate(p[m], y[m])
        per[str(grp)] = {**ev, "n_cal": cp.n_cal, "q_hat": cp.q_hat}
        hits += round(ev["coverage"] * ev["n_test"])
        total += ev["n_test"]
    return {"alpha": alpha, "score": score, "per_group": per,
            "pooled_coverage": hits / total if total else None, "target_coverage": 1.0 - alpha,
            "notes": "Leave-one-group-out; exchangeability across groups is NOT assumed to hold."}
