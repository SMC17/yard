"""Evidence v2 provenance: harness, optimizer budget, seeds, deterministic replay, log export."""

from __future__ import annotations

import json

import numpy as np

from yard_sea_v0.env import DesignSearchEnv
from yard_sea_v0.hull import HullState
from yard_sea_v0.provenance import (
    OptimizerRecord,
    canonical_digest,
    episode_seed,
    load_episode_log,
    verify_log,
)
from yard_sea_v0.search import run_search


def _episode(seed=7, idx=None, steps=4):
    opt = OptimizerRecord(implementation="test.fixed", version="1", settings={"a": 1}, max_evals=steps).start()
    env = DesignSearchEnv(parent=HullState(), max_steps=steps, seed=seed, optimizer=opt)
    opts = {} if idx is None else {"episode_index": idx}
    env.reset(seed=seed, options=opts)
    a = np.zeros(7, dtype=np.float32)
    a[3] = -0.2
    for _ in range(steps):
        env.step(a)
    env.claim_done(require_improvement=False)
    return env


def test_pack_has_harness_optimizer_seeds():
    env = _episode()
    pack = env.evidence_packs[0]
    assert pack["schema"] == "yard_sea_v0.evidence.v2"
    h = pack["harness"]
    assert h["name"] == "yard_sea_v0" and h["version"] and "numpy" in h
    o = pack["optimizer"]
    assert o["implementation"] == "test.fixed" and o["settings"] == {"a": 1}
    assert o["budget"]["max_evals"] == 4 and o["used"]["evals"] >= 1
    s = pack["seeds"]
    assert s["base_seed"] == 7 and s["episode_index"] == 0
    assert s["episode_seed"] == episode_seed(7, 0)
    # L1 default is Zig HM1984 when yard_sea_zig is built, else Python fallback.
    assert pack["oracle"]["fidelity"] in ("hm1984_zig", "simplified_py")


def test_budget_accounting_counts_every_step():
    env = _episode(steps=5)
    assert env.optimizer.evals == 5
    assert env.optimizer.budget_exhausted


def test_seeded_reset_is_deterministic_and_shared():
    a, b = _episode(seed=3), _episode(seed=3)
    assert a.episode_id == b.episode_id
    assert [canonical_digest(p) for p in a.evidence_packs] == [canonical_digest(p) for p in b.evidence_packs]
    # Same (base_seed, episode_index) => identical env RNG stream (common random numbers).
    assert a.np_random.random() == b.np_random.random()
    c = _episode(seed=4)
    assert c.episode_id != a.episode_id


def test_episode_index_changes_seed():
    assert episode_seed(1, 0) != episode_seed(1, 1)
    env = DesignSearchEnv(parent=HullState(), seed=1)
    env.reset()
    first = env.seeds["episode_seed"]
    env.reset()
    assert env.seeds["episode_index"] == 1 and env.seeds["episode_seed"] != first


def test_export_log_roundtrip_and_tamper_detection(tmp_path):
    env = _episode()
    p = tmp_path / "ep.jsonl"
    footer = env.export_log(str(p))
    assert footer["n_records"] == len(env.evidence_packs)
    assert verify_log(p)
    log = load_episode_log(p)
    assert log["header"]["schema"] == "yard_sea_v0.episode_log.v1"
    assert log["header"]["seeds"]["base_seed"] == 7
    assert log["records"][-1]["type"] == "claim"
    lines = p.read_text().splitlines()
    rec = json.loads(lines[1])
    rec["record"]["reward"] = 99.0
    lines[1] = json.dumps(rec)
    p.write_text("\n".join(lines) + "\n")
    assert not verify_log(p)


def test_replay_logs_have_identical_digest(tmp_path):
    f1 = _episode(seed=11).export_log(str(tmp_path / "a.jsonl"))
    f2 = _episode(seed=11).export_log(str(tmp_path / "b.jsonl"))
    assert f1["log_digest"] == f2["log_digest"]


def test_run_search_rows_carry_optimizer_and_shared_seed():
    rows = run_search([HullState()], steps=5, seed=2)
    rand, hill = [r for r in rows if r["method"] in ("random", "hillclimb")]
    for r in (rand, hill):
        assert r["optimizer"]["budget"]["max_evals"] == 5
        assert r["optimizer"]["used"]["evals"] == 5
        assert r["optimizer"]["version"]
    assert rand["seeds"] == hill["seeds"]  # CRN across policies
    assert rand["optimizer"]["implementation"].endswith("random")
