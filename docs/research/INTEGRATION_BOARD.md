# Yard + Strip — living integration board
Updated: 2026-09-10 · OSINT / public only

## Mission
CAD-coupled long-horizon RL/harness platforms that search aero/naval design space under physics **and** evidence. Absorb public S&T + startup ideas; never classified/CUI/ITAR.

## Positioning vs startups (what we steal vs ignore)

| Player | Steal | Ignore / don't clone | Threat |
|---|---|---|---|
| **PhysicsX** | Multi-fidelity: surrogate for search, classical for certify; LPM framing | Claiming to delete solvers entirely | H (capital, defense customers) |
| **Neural Concept** | CAD-native geometry + physics-aware early explore; design *sets* not one concept | Closed proprietary training data moat | H |
| **Compute Maritime / NeuralShipper** | GenAI hull → STAR-CCM+ validation ladder; NVIDIA accel pattern | Their proprietary 100k hull corpus | **H (direct sea peer)** |
| **Luminary Cloud** | Production aero CFD cloud UX, validation discipline | Being "just cloud CFD" | M (air) |
| **Rescale / SimScale** | HPC orchestration, democratized CAE access | Horizontal infra without evidence OS | L–M |
| **nTop** | Field/implicit geometry + manufacturing constraints in the design object | Full CAD replacement | M (geometry ideas) |
| **Synera / Quanscient / Secondmind / Monolith** | Workflow automation, Bayesian opt, sparse industrial data | Scattered horizontal tools | L–M |
| **Ansys/Synopsys AI, Siemens Simcenter** | Incumbent genAI hooks; STAR-CCM+ as L3 teacher | Competing inside PLM | H (distribution) |
| **NVIDIA PhysicsNeMo** | Open neural operators / DoMINO recipes | Vendor lock on stack | M (enabler) |
| **Akselos** | Real-time twin for structures (energy) | Oil/gas-only GTM | L |

**Our wedge they underserve:** every candidate emits an **assurance/evidence pack** (ODD, fidelity tag, monitors, GSN stub). Surrogate speed without fail-closed claims is table stakes now — PhysicsX/Neural Concept sell speed; we sell **search that can prove what it claims**.

## Open ecosystems to wire (priority order for Yard-Sea-v0)

1. Ship-D / C-ShipGen / ShipGen — parametric hull + generative prior  
2. Gymnasium — RL API  
3. BoTorch — Bayesian opt baseline before RL  
4. CadQuery / OCCT — watertight geometry  
5. OpenFOAM (subset) — L3 calm-water teacher  
6. ITTC procedure metadata — V&V language  
7. Strip assurance vocab — FAA/F3269/AMLAS/GSN onto sea gym  
8. Later: OpenVSP + NeuralFoil + JSBSim (air gym same harness)  
9. Later: DAFoam / OpenMDAO patterns; JAX-Fluids sandbox  

## Top ideas to integrate in 90 days

1. Multi-fidelity ladder (L0 algebraic → L1 surrogate → L3 CFD) — PhysicsX/Neural Concept pattern  
2. Runtime monitors reject illegal actions pre-CFD — ASTM F3269  
3. Reward-directed / constrained generative prior — C-ShipGen / ShipGen  
4. PPO/SAC sequential morph with hydrostatic continuity — JCDE RL hull  
5. Evidence JSON every episode (MASS ODD + DNV-style claim/evidence)  
6. Design *gallery* UX (Pareto board) — Neural Concept "design sets"; Yard arena/web reuse  
7. Human-in-loop gate before any "promote to high fidelity" — ARP6983 Issue-1 posture  
8. Reproduce one public baseline (drag shift / constraint SAT rate) as CI fixture  
9. Competitor watch: Compute Maritime + PhysicsX weekly  
10. N251-D07 / CREATE-SHIPS *public claims* as north-star language (not code)  

## Explicit non-goals (90 days)
Full Maxsurf/NAPA clone · stealth/TS optimization · learning-in-ops on vehicles · CREATE binaries · dual sea+air gyms at once · resurrecting 77 yard-* leaves  

## Spec pointers
- `docs/gym/YARD_SEA_V0.md`
- `docs/research/INTAKE.md`
