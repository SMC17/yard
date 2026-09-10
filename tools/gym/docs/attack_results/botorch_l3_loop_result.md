# BoTorch + L3_rans loop — Yard-Sea-v0

**Date:** 2026-09-10 ~5:55 PM ET (America/New_York)  
**Outcome:** **SUCCESS** — BoTorch is a real opt-in search path (`--botorch`); L3 OpenFOAM forceCoeffs teacher records **Cd** on gallery children (`--l3-openfoam`).

## Goal

1. Make BoTorch default-capable: installable, CLI-gated, runs without error on small budgets (and can improve Ct).
2. Wire `--l3-openfoam` so child STLs go through the forceCoeffs teacher and gallery JSON stores Cd / fidelity (`L3_rans` when simpleFoam coeffs parse).

## Changes

| Area | What |
|---|---|
| `yard_sea_v0/search.py` | `use_botorch=` opt-in; `botorch_available()`; hardened `_botorch_child` (LogEI, Y-standardize, cheap restarts, numpy→tensor fix, parent_index) |
| `yard_sea_v0/cli.py` | `--botorch` flag on `run-search` |
| `yard_sea_v0/gallery.py` | `use_botorch`; child JSON fields `Cd`, `l3_fidelity`, `l3_Ct`, `l3_solver` from teacher |
| `requirements.txt` | Document optional `botorch` / `torch` |
| Tests | `tests/test_botorch_search.py`, `tests/test_l3_gallery_cd.py` (mock L3_rans Cd) |

## Smoke

### BoTorch (`.venv` with botorch 0.18.1 + torch 2.14)

```text
python -m yard_sea_v0 run-search --botorch --parents 1 --steps 5 --out out/botorch_smoke_gallery
→ improved=3, methods random/hillclimb/botorch, no skip
```

Unit: `_botorch_child(..., steps=3)` returns `skipped=False` with finite `ct`.

### L3 gallery Cd (mocked teacher → L3_rans)

`tests/test_l3_gallery_cd.py` patches `run_teacher` to return `Cd=0.1459`, `fidelity=L3_rans`.  
Asserts child JSON has `Cd`, `l3_fidelity`, and `l3_openfoam.Cd`.

### Combined CLI

```text
YARD_SEA_L3_SKIP_SOLVE=1 python -m yard_sea_v0 run-search \
  --botorch --l3-openfoam --parents 1 --steps 4 --out out/botorch_l3_gallery
→ botorch=True l3=True; children carry l3_fidelity=L3_pending when solve skipped
```

Real `L3_rans` forceCoeffs path remains as documented in `out/forcecoeffs_result.md` (hybrid native snappy + Docker simpleFoam).

## Tests

```text
pytest -q tests/test_botorch_search.py tests/test_l3_gallery_cd.py \
  tests/test_search_improves_or_feasible.py tests/test_openfoam_l3.py -k 'not integration'
→ 17 passed
```

## Honesty

- BoTorch optimizes the **L0-gated L1 reward**, not CFD. Short budgets may or may not beat hill-climb.
- `--l3-openfoam` is an **optional expensive teacher** after search; it does not replace L1 ranking inside the BO loop.
- Fidelity labels: `L3_rans` (parsed simpleFoam forceCoeffs), `L3_potential`, or `L3_pending` (skip).
- Not ITTC powering / not class / not DAFoam adjoint.

## Branch

`feat/yard-sea-botorch-l3` on SMC17/yard (`tools/gym/…`) — PR https://github.com/SMC17/yard/pull/6
