# Frontier Vision — Verifiable Physics-Grounded AI for Marine Engineering

**Date:** 2026-07-07  
**Proof level:** Architecture document — not yet validated at scale

## The Compound Thesis

1. **Yard primitives** = auditable ground truth (Zig oracle)
2. **Dataset** = the deliverable (oracle-anchored SFT + multimodal assets)
3. **Small fine-tuned model** = beats frontier LLMs on narrow reliability-sensitive behaviors
4. **Vulkan viz** = deterministic rendering controlled by structured scene graphs
5. **Agent layer** = orchestrates modules, quantifies uncertainty, produces numbers + visuals

Frontier models are 80–90% good at naval architecture. They fail on:
- Free-surface correction omission (~24–42% in our gap audit)
- Numerical drift (~96.5% for qwen2.5-coder:1.5b on held-out eval)
- IS Code threshold confusion
- Overconfidence outside validity envelopes

**You control the oracle.** That is rare and is the moat.

## Public Track (Credibility + Distribution)

| Phase | Timeline | Deliverable |
|-------|----------|-------------|
| 1a | Now | 5k text SFT dataset + gap audit baseline |
| 1b | 6–8 weeks | Multimodal dataset (GZ SVG) + fine-tuned 0.5B–1.5B |
| 1c | 6–8 weeks | Public eval harness + post-FT proof (≥95% GM_corr) |

## Internal Track (Capability + Optionality)

| Phase | Timeline | Deliverable |
|-------|----------|-------------|
| 2 | 2–4 months | Multi-module orchestration + Vulkan 3D hull |
| 3 | 3–6 months | Nonlinear effects + higher-fidelity training data |
| 4 | Ongoing | Closed-loop optimization + FMI coupling |

## Commercial Paths (Proper Channels Only)

- **Quant / shipping P&L:** Vessel performance digital twins, scenario generation
- **Venues / infrastructure:** Structural + environmental response viz for temporary works
- **Ports / logistics:** Terminal digital twins, decarbonization pathway modeling
- **Defense-adjacent:** ONR / Navy labs / cleared primes via SBIR/OTA only

## What We Do NOT Claim

- Class-society grade V&V (yet)
- Production-ready full-ship solver
- Regulatory submission without independent expert review

## Ruthless Priorities

1. Prove fine-tune moved behavior into weights (ablation required)
2. Publish multimodal dataset with oracle-verified renders
3. Stop adding primitives until core 6–8 modules compose cleanly
4. Unify licensing (done: Apache-2.0)