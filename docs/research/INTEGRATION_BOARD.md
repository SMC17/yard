# Yard + Strip — living integration board
Updated: 2026-09-10 · OSINT / public only

## Mission
CAD-coupled long-horizon RL/harness platforms that search aero/naval design space under physics **and** evidence. Absorb public S&T + startup ideas; never classified/CUI/ITAR.

**Wedge:** peers sell faster physics / more variants. We sell **search under evidence** — every candidate ships ODD, fidelity, monitors, residuals/uncertainty, provenance. CAD is the action space.

## Positioning vs startups (steal vs ignore)

| Player | Steal | Ignore | Threat |
|---|---|---|---|
| **PhysicsX** (~$2.4B) | Lifecycle physics-AI narrative; multi-fidelity search→certify | Closed LPM SaaS; “delete solvers” | **H** |
| **Neural Concept** | CAD-native design *sets*; intent→geometry→multiphysics | Proprietary training moat | **H** |
| **Compute Maritime / NeuralShipper** | GenAI hull → STAR-CCM+ ladder; manufacturing/class constraints; NVIDIA accel | Proprietary 100k hull corpus; CTV marketing | **H (Yard peer)** |
| **Luminary Cloud** | Solver→DB→surrogate pipeline; aero OEM patterns | Pure cloud CFD economics | **H Strip / M Yard** |
| **Rescale** | Agentic orchestration over solvers; FedRAMP/DoD path | HPC middleware identity | **M** |
| **SimScale** | Agent-from-RFQ; API/Slack report agents | Mid-market CAE without evidence OS | **M** |
| **nTop** | Failure-free parametric regen under DOE; agent-skillable geometry | AM/lattice product surface | **H (geometry)** |
| **Synera** | Auditable connector agents across CAx (80+ tools) | Low-code without physics core | **M** |
| **Quanscient** | Python-first multiphysics API for agent loops | Quantum narrative near-term | **L–M** |
| **Secondmind** | Uncertainty-aware sample efficiency; feasible-region boxes | Auto calibration niche | **L** |
| **Monolith → CoreWeave** | Test-plan / sim-to-real Field Eng (launched 2026-09-10) | Hyperscaler bundling | **M** |
| **Akselos** | Reduced-order physics with **computable error bars** | Ops integrity SPM, not generative search | **L** (steal evidence pattern) |
| **Ansys/Synopsys AI** | GeomAI / SimAI / mesh agents | Incumbent lock-in | **H** |
| **Siemens Simcenter** | PhysicsAI Generate; STAR-CCM+ as L3 teacher | Portfolio noise; already partners NeuralShipper | **H** |
| **NVIDIA PhysicsNeMo** | Open LPM training substrate (nn/mesh/diffusion) | Over-coupling to CUDA/Omniverse | **H ecosystem / L product** |
| **HydroGym / FluidGym** | Gymnasium CFD env packaging; HF artifact discipline | Flow-*control* bias vs design-search | **M (infra)** |
| **MIT DeCoDE (Ship-D / C-ShipGen)** | Parametric hull latent + drag guidance; dataset-first | Not a product; resistance-only early | **M (Yard seed)** |

## Open ecosystems to wire

1. Ship-D / C-ShipGen — corpus + generative prior  
2. Gymnasium + HydroGym patterns — DesignSearchEnv API  
3. BoTorch — outer loop before RL burns CFD  
4. CadQuery / OCCT — every action emits valid CAD  
5. OpenFOAM subset / DAFoam — L3 teacher + sparse adjoint  
6. OpenMDAO — physics graph for coupled disciplines  
7. Strip assurance vocab (FAA/F3269/AMLAS/GSN) on sea gym  
8. PhysicsNeMo — train *our* surrogates on *our* evidence  
9. Later: OpenVSP + NeuralFoil + JSBSim (Strip parallel)  
10. ITTC metadata — V&V language  

## Top 15 absorb in 90 days

1. Ship-D → Yard corpus + Zig hull param schema  
2. C-ShipGen as proposal prior (class/human gates kept)  
3. CadQuery action space (CAD-native or die)  
4. Gymnasium DesignSearchEnv  
5. BoTorch outer loop (Secondmind pattern)  
6. OpenMDAO physics graph  
7. Cheap hydro surrogate + NeuralFoil (Strip) for ms rewards  
8. OpenVSP→JSBSim smoke (Strip parallel, same harness)  
9. DAFoam sparse oracle for surrogate/RL verification  
10. nTop-style zero-fail regen contract  
11. PhysicsNeMo training substrate (don’t buy PhysicsX)  
12. HydroGym packaging / HF checkpoint discipline  
13. Synera-style audited CAD↔solver↔evidence connectors  
14. Akselos-style residual/uncertainty on every claim  
15. NeuralShipper-class manufacturability + class constraints in reward  

**Defer:** quantum CFD, Rescale/SimScale as primary compute, Ansys/Siemens GenAI as product, CoreWeave FDE model.

## Positioning one-liner
Vs PhysicsX/Neural Concept: they sell faster physics; we sell **search under evidence**.  
Vs NeuralShipper: they generate hulls; we **govern long-horizon design search with class-grade evidence**.

## Explicit non-goals (90 days)
Maxsurf/NAPA clone · stealth/TS · learning-in-ops · CREATE binaries · dual sea+air full build · resurrecting 77 `yard-*` leaves · LPM fundraising narrative

## Spec pointers
- `docs/gym/YARD_SEA_V0.md`
- `docs/research/INTAKE.md`
