# Act45 — full 45-D Ship-D action space — RESULT

**Date:** 2026-09-10 (America/New_York)  
**Repo:** `/workspace/yard-sea-v0/`  
**Goal:** True Gymnasium `Box(45)` actions on DesignSearchEnv45 (not 7-D principal morph).

## Success criteria (honest)

| Criterion | Status |
|-----------|--------|
| Rewrite/extend `env45.py` for true 45-D actions | **PASS** — `DesignSearchEnv45.action_space = Box(45)`; deltas on full Ship-D vector |
| Relative deltas, clamp to dataset-ish ranges | **PASS** — scales = 5% of 30k 1–99% span (`data/shipd_action_bounds.json`); bits snap to {0,1} |
| Step: delta → `evaluate_constraints` → reject before L1 if fail | **PASS** — `shipd_infeasible` + monitor `shipd_algebraic_constraints` |
| If ok: `project_to_hull` → L0 → L1 + evidence | **PASS** — surface hydrostatics **not** used per-step (HP volumes need PCMeasurement; reserved hook `hull_from_shipd`) |
| Keep `DesignSearchEnv` (7-D) intact | **PASS** — unchanged action path |
| Tests: zeros / infeasible reject / feasible morph L0-gated | **PASS** — `tests/test_env45.py` |
| CLI flag or `__init__` export | **PASS** — `DesignSearchEnv45` + `ACTION_DIM` exported; `act45` subcommand + `run-search --env45` |
| `STATUS.md` updated | **PASS** |
| `out/act45_result.md` | **PASS** (this file) |
| Related pytest | **PASS** — full suite **68 passed** (2026-09-10) |

## What landed

| Piece | Path |
|-------|------|
| Env | `yard_sea_v0/env45.py` — `DesignSearchEnv45`, `apply_shipd_delta`, `ACTION_DIM=45` |
| Bounds | `yard_sea_v0/shipd.py` — `load_action_bounds`, `action_scales`, `BIT_INDICES` |
| Bounds cache | `yard_sea_v0/data/shipd_action_bounds.json` (30k p01–p99) |
| Search helper | `yard_sea_v0/search.py` — `run_env45_search` |
| CLI | `act45` smoke; `run-search --env45` |
| Export | `yard_sea_v0/__init__.py` — `DesignSearchEnv45`, `ACTION_DIM` |
| Tests | `tests/test_env45.py` (zeros, infeasible Lb/Ls push, feasible morph, clamp/bits) |

## Step semantics

```text
action ∈ [-1,1]^45
proposed = clamp(current + action * scales, lo_p01, hi_p99); bits → {0,1}
if not evaluate_constraints(proposed).feasible:
    reject (monitor), reward=-1, state unchanged   # before L1
else:
    hull = project_to_hull(proposed)
    if not L0(hull):
        reject (monitor), reward=-1                 # before L1
    else:
        commit shipd_vector + hull; L1 reward; evidence pack
```

## Smoke observed

```text
act45 sample=0 zero rejected=False shipd_infeas=False reward≈0.10
act45 random_steps=7 rejected=2 shipd_infeasible=0 action_dim=45
run-search --env45 --parents 2 --steps 5 → episodes=2 with_accepts=2
pytest: 68 passed
```

## Honesty / non-claims

- **Not** ITTC powering, class society, FAA/ops, ITAR.
- LOA is constant (=10) in the public 30k sample → action scale on LOA is 0 (frozen).
- Hull for L1 remains the **exploratory projection** (`project_to_hull`), not volume-accurate Ship-D hydrostatics.
- 7-D `DesignSearchEnv` / gallery default path unchanged; use `--env45` / `act45` for 45-D.
- No GitHub push from this agent.
