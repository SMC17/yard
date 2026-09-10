# Ship-D HP primary geometry/hydro ranking — RESULT

**Date:** 2026-09-10 (America/New_York)  
**Repo:** `/workspace/yard-sea-v0/` → `SMC17/yard` `tools/gym/`  
**Branch:** `feat/yard-sea-hp-primary`  
**Goal:** Make `Hull_Parameterization` the **primary** geometry/hydro path for 45-D ranking (not just projection to box `HullState`).

## Success criteria

| Criterion | Status |
|-----------|--------|
| Ranking path uses `calc_volumes` + Ship-D STL + Michell-from-HP when vector is 45-D | **PASS** — `yard_sea_v0/hp_rank.py` `rank_shipd` |
| `project_to_hull` fallback only | **PASS** — `geometry_source=project_fallback` on vendor miss / `prefer_hp=False` / HP exception |
| Env45 `use_hp_geometry=True` default when `shipd_surface` available | **PASS** — default via `hp_geometry_default()` |
| Tests | **PASS** — `tests/test_hp_rank.py` + updated `test_env45.py` |
| RESULT markdown | **PASS** — this file |
| Push + PR | **PASS** — https://github.com/SMC17/yard/pull/8 |

## What landed

| Piece | Path |
|-------|------|
| Primary rank API | `yard_sea_v0/hp_rank.py` — `rank_shipd`, `hull_from_shipd_primary`, `HPRankResult` |
| Env45 flag | `use_hp_geometry` (default True if vendor present); implies `use_hp_hydro` + `hp_hydro_every_n=1` |
| Search | `search.run_env45_search(..., use_michell_rank=)` records HP geometry + optional final Michell/STL |
| Gallery / corpus | Ship-D parents via HP volumes; `--shipd` + `--l15-michell` uses HP waterlines; Ship-D STL when vectors known |
| Michell | `teachers.michell_l15.run(vector=…)` builds hull via HP primary (not bare `project_to_hull`) |
| Tests | `tests/test_hp_rank.py`, env45 default-on / disable / step geometry assertions |

## Ranking contract (45-D)

```python
from yard_sea_v0.hp_rank import rank_shipd
from yard_sea_v0.shipd import load_sample_vectors

r = rank_shipd(load_sample_vectors()[0], use_michell=True, stl_path="out/hp.stl")
assert r.geometry_source == "hp"
assert r.michell["offset_source"] == "shipd_hp_waterlines"
```

Order:

1. `calc_volumes` → `hull_from_volumes` (Cb / LCB from surface)
2. optional `generate_stl` (HP surface)
3. optional Michell L1.5 with `vector=` → HP waterlines
4. L1 Holtrop-simplified on the HP-refined `HullState`
5. **fallback:** `project_to_hull` only

## Env45 defaults

```python
env = DesignSearchEnv45(sample_index=0)  # use_hp_geometry=True when vendor present
obs, info = env.reset()
assert info["use_hp_geometry"] is True
assert info["geometry_source"] == "hp"
# accepted steps refresh calc_volumes every step (hp_hydro_every_n=1)
```

Disable:

```python
DesignSearchEnv45(..., use_hp_geometry=False, use_hp_hydro=False)
```

## Spot check (sample 0)

| Metric | Value |
|--------|------:|
| geometry_source | `hp` |
| volume (m³) | ~6.822 |
| L1 Ct | ~0.003489 |
| Michell Cw | ~2.79e-4 |
| offset_source | `shipd_hp_waterlines` |
| STL bytes (16×32) | ~95k |

## Tests

```sh
cd /workspace/yard-sea-v0 && source .venv/bin/activate
PYTHONPATH=. pytest -q tests/test_hp_rank.py tests/test_env45.py
# focused HP + env45 + surface + Michell: 33 passed
# broader (botorch/corpus/michell/multifidelity/openfoam + HP): 55 passed
```

## Honesty / not claimed

- Not ITTC powering, not class society hydrostatics, not operational.
- HP volumes/waterlines are exploratory Ship-D surface math.
- L1 remains Holtrop-simplified; Michell is L1.5 thin-ship ranking only.

## Push

- Branch: `feat/yard-sea-hp-primary`
- PR: https://github.com/SMC17/yard/pull/8 (base `feat/yard-sea-remaining-stones`)
- Prefer separate branch over dumping onto multifidelity WIP.
