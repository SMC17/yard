"""Split-conformal utility + yard applications (LF vs L1.5, oracle vs towing tank)."""

from __future__ import annotations

import math

import numpy as np
import pytest

from yard_sea_v0.conformal import (
    ASSUMPTIONS,
    LABEL,
    SplitConformal,
    conformal_quantile,
    group_cv,
    min_calibration_size,
    random_split_coverage,
)
from yard_sea_v0.conformal_yard import lf_hf_conformal, sample_hulls, tank_conformal
from yard_sea_v0.env import DesignSearchEnv
from yard_sea_v0.hull import evaluate_l0


def test_quantile_rank_and_infinite_when_too_few():
    s = np.arange(1.0, 10.0)  # n = 9
    assert conformal_quantile(s, 0.1) == 9.0  # ceil(10*0.9) = 9th smallest
    assert conformal_quantile(s[:8], 0.1) == math.inf
    assert min_calibration_size(0.1) == 9 and min_calibration_size(0.2) == 4


def test_marginal_coverage_on_exchangeable_data():
    rng = np.random.default_rng(1)
    p = rng.uniform(1.0, 2.0, 400)
    y = p * (1.0 + 0.1 * rng.standard_normal(400))
    out = random_split_coverage(p, y, alpha=0.1, score="rel", n_splits=300)
    assert 0.88 <= out["mean_coverage"] <= 0.94


def test_abs_and_rel_intervals():
    cp = SplitConformal(0.5, "abs").fit([1.0, 2.0, 3.0], [1.1, 2.3, 2.6])
    lo, hi = cp.interval(10.0)
    assert hi - lo == pytest.approx(2 * cp.q_hat)
    cr = SplitConformal(0.5, "rel").fit([1.0, 2.0, 4.0], [1.1, 2.2, 4.4])
    lo, hi = cr.interval(10.0)
    assert (lo, hi) == pytest.approx((9.0, 11.0))


def test_group_shift_breaks_coverage_and_is_reported():
    rng = np.random.default_rng(0)
    groups = np.repeat(["a", "b", "c", "d"], 30)
    bias = {"a": 0.0, "b": 0.0, "c": 0.0, "d": 0.5}
    p = rng.uniform(1, 2, 120)
    y = np.array([pi * (1 + bias[g] + 0.05 * rng.standard_normal()) for pi, g in zip(p, groups)])
    out = group_cv(p, y, groups, alpha=0.1, score="rel")
    assert out["per_group"]["d"]["coverage"] < 0.5  # the shifted group is not covered
    assert "NOT assumed" in out["notes"]


def test_sampler_is_l0_feasible_and_seeded():
    a, b = sample_hulls(20, 3), sample_hulls(20, 3)
    assert [h.as_vector() for h in a] == [h.as_vector() for h in b]
    assert all(evaluate_l0(h).feasible for h in a)


def test_lf_hf_conformal_record_into_env_evidence():
    rec = lf_hf_conformal(80, alpha=0.1, seed=2)
    assert rec["label"] == LABEL and rec["assumptions"] == ASSUMPTIONS
    assert rec["finite"] and rec["q_hat"] > 0 and rec["test"]["n_test"] > 0
    assert 0.8 <= rec["random_splits"]["mean_coverage"] <= 1.0
    env = DesignSearchEnv(max_steps=2)
    env.reset(seed=0)
    stored = env.record_evidence(rec)
    assert stored["type"] == "conformal_calibration" and stored in env.evidence_packs


def test_tank_conformal_reports_leave_one_hull_out():
    rec = tank_conformal("simplified_py", alpha=0.2)
    assert rec["available"] and rec["n_points"] >= 8
    loho = rec["leave_one_hull_out"]
    assert set(loho["per_group"]) == set(rec["hulls"])
    assert 0.0 <= loho["pooled_coverage"] <= 1.0
