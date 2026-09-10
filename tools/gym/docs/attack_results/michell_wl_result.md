# Michell L1.5 — Ship-D waterline offsets — RESULT

**Date:** 2026-09-10 (America/New_York)  
**Goal:** Replace Wigley-only Michell offsets with real Ship-D waterline offsets for Yard-Sea-v0 Michell L1.5.  
**Honesty:** not ITTC powering · not class · not operational · exploratory L1.5 ranking only

## Success criteria

| Criterion | Status |
|-----------|--------|
| Waterline extraction Ship-D vector → Michell (Y,X,Z) | **PASS** — `shipd_waterline_offsets` via HP `gen_MeshGridWL` |
| `michell_l15.run(vector=…)` uses Ship-D WL; Wigley fallback | **PASS** — `offset_source`: `shipd_hp_waterlines` / `wigley_synthetic` / `provided` |
| Tests: finite Cw on sample Ship-D vectors vs Wigley | **PASS** |
| RESULT markdown | **PASS** — this file |
| No GitHub push | **PASS** |

## Implementation

### Extraction (`yard_sea_v0/teachers/michell_l15.py`)

- `shipd_waterline_offsets(vector, nx, nz, draft=None)` builds HP via `shipd_surface._hull_param`
- Samples each submerged height with `Hull_Parameterization.gen_MeshGridWL`
- Interpolates half-breadth onto uniform stations `X ∈ [0, LOA]` (Nx forced odd for Filon)
- Maps Ship-D `z` (keel=0 … WL=`hp.WL`) → Michell `Z` (FS=0 … keel=`-T`)
- Forwarder: `shipd_surface.michell_waterline_offsets`

### Teacher wiring

`run(...)` offset priority:

1. Explicit `Y` / `X` / `Z`
2. Length-45 `vector` → Ship-D HP waterlines
3. Wigley synthetic from `HullState`

When only `vector` is passed, hull principals come from `project_to_hull`.

## Spot checks (Fn=0.20, nx=31, nz=9, n_theta=20)

| Sample | LOA [m] | T [m] | Y_max [m] | Cw (Ship-D WL) | Rw [N] | Cw (Wigley proj.) |
|--------|---------|-------|-----------|----------------|--------|-------------------|
| 0 | 10.0 | 0.628 | 0.875 | 2.82e-4 | 56.6 | 3.67e-4 |
| 3 | 10.0 | 0.070 | 0.177 | 1.44e-5 | 2.89 | 2.44e-4 |
| 9 | 10.0 | 0.174 | 0.531 | 1.61e-5 | 3.24 | 4.40e-5 |

Ship-D waterline Cw is finite, positive, and distinct from the Wigley projection of the same principals (as expected — different half-breadth shapes).

## Tests

```sh
cd /workspace/yard-sea-v0 && source .venv/bin/activate
PYTHONPATH=. pytest -q tests/test_michell_l15.py
# 8 passed
```

New coverage:

- `test_shipd_waterline_offsets_shape_and_positive`
- `test_run_shipd_vector_finite_cw_differs_from_wigley`
- `test_run_shipd_multiple_samples_finite`

## How to exercise

```python
from yard_sea_v0.shipd import load_sample_vectors
from yard_sea_v0.teachers.michell_l15 import run, shipd_waterline_offsets

vec = load_sample_vectors()[0]
Y, X, Z = shipd_waterline_offsets(vec, nx=41, nz=11)
r = run(vector=vec, Fn=0.20)  # offset_source == "shipd_hp_waterlines"
```

## Hard stops / deferred

- Bulb overhangs with `x < 0` are clipped to the `[0, LOA]` Michell grid (Y=0 outside waterline extent)
- Gallery `--l15-michell` still uses HullState/Wigley unless a Ship-D `vector` is passed into `run`
- Still not ITTC powering / model-test validated
- No GitHub push

## Artifacts

- `yard_sea_v0/teachers/michell_l15.py` — `shipd_waterline_offsets`, `run(vector=…)`
- `yard_sea_v0/shipd_surface.py` — `michell_waterline_offsets` forwarder
- `tests/test_michell_l15.py`
- `docs/STRIP_ORACLES.md` — L1.5 row updated
