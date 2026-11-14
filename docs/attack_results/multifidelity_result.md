# Multi-fidelity design-search — Yard-Sea-v0

**Date:** 2026-09-10 ~7:05 PM ET (America/New_York)  
**Outcome:** **SUCCESS** — Stage A cheap L1 (/optional L1.5) → Stage B L3_rans on top-k elites; cost-aware BoTorch approximation documented; gallery records `fidelity_ladder` per child.

## Goal

Push Yard-Sea-v0 past “BoTorch + optional L3 on every child” into a real multi-fidelity loop:

1. **Stage A** — random / hill-climb / BoTorch on L1 (optional Michell L1.5 mid-fidelity).
2. **Stage B** — top-k elites by Stage-A score → OpenFOAM L3 forceCoeffs teacher → re-rank by Cd/Ct.
3. **Cost-aware acquisition** when BoTorch is available (or document approximation).

## CLI

```sh
python -m yard_sea_v0 run-search --multifidelity --l3-top 3 --botorch \
  --parents 2 --steps 8 --out out/mf_gallery

# optional mid-fidelity on Stage A
python -m yard_sea_v0 run-search --multifidelity --l3-top 2 --l15-michell --botorch ...

# plain EI instead of cost-weighted qLogEI
python -m yard_sea_v0 run-search --multifidelity --botorch --no-cost-aware ...
```

## Implementation

| Area | What |
|---|---|
| `yard_sea_v0/multifidelity.py` | Cascade loop: Stage A → `select_elites` → `evaluate_l3_elites`; `fidelity_ladder`; costs L1=1 / L1.5=20 / L2=80 / L3=2000; cost-aware `botorch_mf` via qLogEI + `InverseCostWeightedUtility` (constant L1 cost) |
| `yard_sea_v0/gallery.py` | `--multifidelity` path records ladder + elite L3 summaries in manifest |
| `yard_sea_v0/cli.py` | `--multifidelity`, `--l3-top K`, `--no-cost-aware` |
| Tests | `tests/test_multifidelity.py` — mocked L3_rans, elite gating, CLI flags, BoTorch cost-aware smoke |

### Cost-aware honesty

BoTorch’s continuous **qMultiFidelityKnowledgeGradient** is **not** used. Primary cost control is the **cascade gate** (L3 only on elites). When `--botorch` + cost-aware (default), Stage A uses **qLogExpectedImprovement** with **InverseCostWeightedUtility** and a **constant L1 cost model**. That is an approximation of cost-aware MF acquisition — documented in `COST_AWARE_NOTES` on each `botorch_mf` child and in the MF summary.

## Smoke

### Unit (mocked L3)

```text
pytest -q tests/test_multifidelity.py
→ 6 passed
```

### CLI (FOAM solve skipped)

```text
YARD_SEA_L3_SKIP_SOLVE=1 python -m yard_sea_v0 run-search \
  --multifidelity --l3-top 1 --botorch --parents 1 --steps 3 \
  --out out/mf_smoke_gallery
→ mf=True l3_top=1 botorch=True; 1 elite; children carry fidelity_ladder
```

Elite gets L3 teacher call (pending when solve skipped); non-elites get `skip_reason=not_elite_cost_gate`.

### Live FOAM

OpenFOAM available on this box (`native_forces_ok` via sha1 preload + docker). Live L3_rans elite smoke remains optional / expensive; mocked path covers the ladder + gate contract. Real forceCoeffs teacher unchanged (`teachers/openfoam_l3.py`).

## Fidelity ladder (per child)

```json
"fidelity_ladder": [
  {"level": "L1_holtrop_simplified", "cost": 1.0, "Ct": 0.004, "teacher": "resistance_l1"},
  {"level": "L3_rans", "cost": 2000.0, "Cd": 0.14, "teacher": "openfoam_l3", "skipped": false}
]
```

Non-elites record an `L3_pending` step with `skip_reason=not_elite_cost_gate` and cost 0.

## Honesty

- Stage A optimizes L0-gated **L1** reward (BoTorch), not CFD.
- Stage B re-ranks elites by **Cd** (preferred) / L3 Ct — exploratory ranking, **not ITTC powering / not class**.
- Cost units are relative wall-clock guesses, not measured FLOPs.
- Not DAFoam adjoint / not continuous MF-KG.

## Branch

`feat/yard-sea-multifidelity` on SMC17/yard (`tools/gym/…`)
