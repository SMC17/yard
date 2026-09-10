# Ship-D surface + 49 constraints — RESULT

**Date:** 2026-09-10 (America/New_York)  
**Repo:** `/workspace/yard-sea-v0/`  
**Goal:** Real constraint eval + STL from Ship-D params, locally with pytest.

## What landed

| Piece | Path |
|-------|------|
| Vendored upstream | `vendor/shipd_upstream/` (`HullParameterization.py`, `STLGen.py`, helpers, `X_LABELS.npy`, README) |
| Wrapper | `yard_sea_v0/shipd_surface.py` — `evaluate_constraints`, `generate_stl`, `to_hull_state` |
| Schema bridge | `yard_sea_v0/shipd.py` — `constraint_checklist` status + `is_feasible` |
| Mesh API | `yard_sea_v0/mesh.py` — `write_shipd_stl` |
| Env gate | `yard_sea_v0/env45.py` — constraint report on reset; reject before L1 if infeasible |
| Gallery filter | `yard_sea_v0/gallery.py` — `shipd_parents` requires algebraic feasibility |
| Corpus hook | `yard_sea_v0/corpus.py` already calls `evaluate_constraints` when present |
| Deps | `requirements.txt`: `numpy-stl`, `matplotlib` (+ existing numpy/gymnasium/pytest) |
| Tests | `tests/test_shipd_surface.py` (+ updated `test_shipd.py`, `test_env45.py`) |
| Demo STL | `out/shipd_surface/sample3_nobulb.stl` |
| Status | `STATUS.md` updated (honest: not class/ITTC) |

## Commands

```sh
cd /workspace/yard-sea-v0
.venv/bin/pip install -r requirements.txt
PYTHONPATH=. .venv/bin/pytest -q
# or with pytest.ini pythonpath:
.venv/bin/pytest -q
```

Observed locally: **49 passed** (includes corpus / zig / openfoam skip-or-pass tests already in tree).

Ship-D surface-focused checks in `test_shipd_surface.py`:

- constraint eval length 49 on all 12 sample vectors (all feasible)
- synthetic infeasible vector flags `general` group
- STL write via `generate_stl` and `write_shipd_stl`
- reject infeasible before mesh

## Constraint semantics (upstream)

```text
constraints = Hull.input_Constraints()   # 49 floats
feasible iff sum(constraints > 0) == 0   # g(x) <= 0
```

Groups: general(2) + cross(7) + bow(15) + stern(12) + bulb(13) = **49**.

## Vendor patches (NumPy 2)

Documented in `vendor/shipd_upstream/README.md`:

1. `np.trapz` → shim to `np.trapezoid` when missing  
2. `halfBeam_BB(...)[0]` missing index in `gen_waterline_bow_BB` (array→scalar assign)

## Blockers / honesty

- **Not claimed:** ITTC powering, class society, FAA/ops, ITAR.
- env45 action space is still **7-D principal morph**; constraints gate the **seed** 45-D vector (samples pass). Full 45-D actions remain future work.
- Harvard Dataverse **30k** corpus ingest / license is separate (`corpus.py` may download `InputVectors_30k.npy`).
- CadQuery/OCCT B-rep remains optional; Ship-D STL is the parametric **HP surface** (numpy-stl), not class-approved geometry.
- Do **not** push from this agent — parent will push.

## Quick manual check

```sh
PYTHONPATH=. .venv/bin/python - <<'PY'
from yard_sea_v0.shipd import load_sample_vectors
from yard_sea_v0.shipd_surface import evaluate_constraints, generate_stl
v = load_sample_vectors()[3]
print(evaluate_constraints(v).to_dict()["feasible"], evaluate_constraints(v).n_violations)
print(generate_stl(v, "out/shipd_surface/manual.stl", num_wl=16, points_per_wl=30))
PY
```
