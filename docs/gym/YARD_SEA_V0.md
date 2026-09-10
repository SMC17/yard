# Yard-Sea-v0 — design gym specification

Status: draft for implementation · 2026-09-10  
Public data only. Not class/FAA/DoD approved.

## Goal
Closed loop: **parametric hull → multi-fidelity physics → long-horizon search → evidence pack**.  
First product of the Yard/Strip “edges of possibility” bet. Air gym reuses the harness later.

## State
- 45-D Ship-D (or C-ShipGen-compatible) parameter vector  
- Hydrostatics: volume, C_B, LCB, wetted area, GM proxy  
- Last-N rewards and constraint flags  
- Fidelity tag of last evaluation (L0/L1/L2/L3)

## Action
- Bounded Δparams **or** residual on a generative prior (stay on manifold)  
- Runtime monitor rejects actions that violate algebraic watertightness / hydrostatic envelopes **before** CFD

## Reward (multi-head)
- −resistance / C_T (Fr, draft)  
- +cargo volume / displacement utility  
- −constraint penalties (self-intersection, T/B, CP/LCB bands)  
- seakeeping **proxy only** in v0 (not full RAO)

## Fidelity ladder
| Level | Physics | Role |
|---|---|---|
| L0 | Algebraic constraints + hydrostatics | Always-on filter |
| L1 | Public drag surrogate (Ship-D / trained) | Inner-loop RL/BO |
| L2 | Potential-flow (optional public code) | Mid |
| L3 | OpenFOAM calm-water on tiny parent set | Rare teacher / CI |

## Search baselines (must beat in CI)
1. Random on manifold  
2. BoTorch Bayesian optimization  
3. Reward-directed / guided diffusion (C-ShipGen-class)  
4. PPO and SAC (Gymnasium)

## Evidence emit (every episode)
JSON including:
- ODD (Fr, draft, heading assumptions, domain limits)  
- fidelity + software versions + seed  
- constraint report  
- GSN stub claim: “hydrostatically feasible & drag reduced vs parent under L1 — **not** ITTC powering”  
- agent class: learned, offline, not learning-in-ops  

Align field names with MASS ODD vocabulary + DNV-RP-0671-style claim/evidence where practical.

## Kill criteria
- Watertightness < 90% on generated set → stop RL, fix geometry  
- L1 vs published Ship-D error is junk → stop RL, fix surrogate  
- Any path that needs CAC/ITAR/CREATE binaries → reject

## 90-day milestones
See `docs/research/INTEGRATION_BOARD.md`. Demo artifact: 20-parent → 20-child gallery with deltas + evidence JSON + GSN diagram.

## Out of scope (v0)
Full seakeeping RANS, CSR FEA, signatures, onboard autonomy, dual-domain air gym.
