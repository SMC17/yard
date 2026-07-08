# v1.0 Hardening Roadmap — SMC17/yard

**Date:** 2026-07-08  
**Status:** Post-consolidation, platform-alpha live  
**Goal:** Move from 0.x platform-alpha to production-grade v1.0

---

## Audit Reconciliation

The 2026-07-07 ruthless audit described a **flat repo** (69 modules only). That snapshot is **stale**. As of 2026-07-08:

| Claim (audit) | Reality (verified) |
|---------------|-------------------|
| No root `build.zig` | ✅ `build.zig` with `test-core`, `test-all`, `run-example`, `run-full-assessment`, `run-seakeeping` |
| No `compose/` | ✅ 4 workflows: `box_barge`, `cargo_resistance`, `vessel_assessment`, `seakeeping_assessment` |
| No `examples/` | ✅ 3 examples + `agent_spec.json` |
| No `PLATFORM.md` | ✅ Live with 4-layer architecture |
| No `tools/{oracle,dataset,eval}` | ✅ Full intelligence stack + gap audit baseline |
| No CI | ✅ `.github/workflows/ci.yml` |
| AGPL license drift | ✅ Unified Apache-2.0 |
| No intelligence proof | ✅ Gap audit: qwen2.5-coder:1.5b 0.5% GM_corr (pre-FT) |

**Still accurate from audit:**

- Zig 0.16 pin (no 1.0 matrix yet)
- Limited benchmark-hull validation (Wigley/box-barge strong; Series 60/KCS pending)
- CSR/structures modules need rule-lawyer pass before class-society claims
- Property/fuzz testing not systematic
- Fine-tune loop incomplete (checkpoint-25 saved; post-FT eval pending)
- Some modules thinner than hydro/stability cores

---

## Milestones

| Milestone | Target | Status |
|-----------|--------|--------|
| **M0** — Audit baseline, root build, all modules compile/test | Week 1 | 🟢 Done |
| **M1** — Priority-1 module hardening (hydro, stability, mass, resistance, seakeeping, csr/*) | Weeks 2–4 | 🟡 In progress |
| **M2** — Composition layer (4+ workflows, examples, PLATFORM) | Weeks 5–8 | 🟡 4 workflows live |
| **M3** — CI matrix, property/fuzz, numerical audit report | Weeks 9–12 | 🔴 Open |
| **M4** — Polish, perf, agent extensions, v1.0 RC tags | Weeks 13–16+ | 🔴 Open |

---

## Layer Status

### Layer 1 — Primitives (69 modules)

**Base checklist (every module → "pass 0.0"):**

- [ ] `zig build test --summary all` green
- [ ] README: API, examples, validation, limitations
- [ ] STATUS / CHANGELOG / NEXT filled
- [ ] `build.zig.zon` minimum_zig_version declared
- [ ] `zig fmt` clean
- [ ] NaN/inf handling documented
- [ ] `root.zig` stable public facade
- [ ] Integration notes (consumes/produces)
- [ ] Bench target works
- [ ] Apache-2.0 license header

**Priority groups:**

| Group | Modules | Depth | v1.0 gate |
|-------|---------|-------|-----------|
| P1 Core | hydro, stability, mass, naval-arch, resistance, seakeeping, strip-theory, rao-spectrum, fossen-6dof | High (sampled) | Benchmark hulls + cross-module property tests |
| P2 Structures | csr, csr-buckling, csr-fatigue, strength, deck, jacket | Medium–High risk | Independent rule verification + fixtures |
| P3 Ops | port-*, mooring, dynpos, routing, eedi, cii | Variable | Workflow integration tests |
| P4 Special | bem, hess-smith-3d, sloshing, submarine, combat | Complex physics | Numerical stability audit |

### Layer 2 — Composition

| Workflow | File | Example | Tests |
|----------|------|---------|-------|
| Box-barge stability | `compose/src/box_barge.zig` | `examples/box-barge-intact-stability/` | ✅ |
| Cargo resistance | `compose/src/cargo_resistance.zig` | — | ✅ |
| Vessel assessment | `compose/src/vessel_assessment.zig` | `examples/full-vessel-assessment/` | ✅ |
| Seakeeping assessment | `compose/src/seakeeping_assessment.zig` | `examples/seakeeping_assessment/` | ✅ + README + standalone build |

**Next workflows:** trim/damage composition, offsets → GZ → IMO full-hull chain.

### Layer 3 — Intelligence

| Component | Path | Status |
|-----------|------|--------|
| Stability oracle | `tools/oracle/yard_stability_oracle.py` | ✅ Proven |
| Seakeeping oracle | `tools/oracle/yard_seakeeping_oracle.py` | ✅ RK4-matched |
| Seakeeping dataset | `tools/dataset/generate_seakeeping.py` | ✅ New |
| Seakeeping gap audit | `tools/gap_audit/gap_audit_seakeeping.py` | ✅ Baseline filed |
| Dataset pipeline | `tools/dataset/` | ✅ 5.2k multimodal |
| Eval harness | `tools/eval/harness.py` | ✅ |
| Agent harness | `tools/agent/harness.py` | ✅ Unified dispatcher |
| Gap audit | `tools/gap_audit/` | ✅ Baseline filed |
| Fine-tune | `tools/finetune/` | 🟡 checkpoint-25; full train pending |

**Fine-tune proof loop (blocked on GPU stability):**

1. Resume/restart from `checkpoint-25`
2. `infer_local.py` on 200-case `eval.jsonl`
3. Update `GAP_REPORT.md` with post-FT numbers
4. Ablation: minimal prompt, FS omission, jailbreak resistance

### Layer 4 — Extensions

- `viz/` Phase 1 (GZ SVG) ✅
- `viz-vulkan/` ROADMAP only
- `tools/cli/yard-cli.py` ✅
- Python FFI / Zig Bean actor patterns — 🔴 future

---

## Repository-Wide Tasks

### Done ✅

- Root `build.zig` workspace orchestration
- `compose/` + `examples/` skeleton
- `PLATFORM.md` + `docs/01–05`
- CI workflow
- Apache-2.0 unification
- Intelligence stack (oracle, dataset, eval, gap audit)
- Seakeeping workflow wired end-to-end

### Open 🔴

1. **Zig version matrix** — test 0.16 + latest on ubuntu/mac, x86_64/aarch64
2. **CONTRIBUTING.md, SECURITY.md** — numerical correctness policy
3. **Benchmark hull fixtures** — Series 60, KCS, DTMB in `codex/validation_fixtures`
4. **Property/fuzz tests** — displaced volume consistency, bad offsets rejection
5. **nats_telemetry gating** — optional feature flag per module
6. **Semver tags** — v0.1.0-platform-alpha → v1.0.0-rc*
7. **Zig package publish strategy** — per-module vs meta-pkg
8. **CSR rule-lawyer audit** — classification-risk modules

---

## Proof Levels

Inherited from `naval-arch/src/types.zig`:

| Level | Meaning | v1.0 requirement |
|-------|---------|------------------|
| `analytical` | Closed-form exact (Wigley, box-barge) | Documented + tested |
| `unit_tested` | Unit tests pass | All P1 modules |
| `benchmark_hull` | vs published hull data | P1 hydro/stability/seakeeping |
| `audited` | Independent review | CSR modules before claims |
| `hardware_verified` | Physical experiment | Out of v1.0 scope |

Never overclaim. Composition workflows ship at `unit_tested` until benchmark hulls are wired.

---

## Sprint Commands

```sh
# Core platform
cd yard && zig build test-core
zig build run-example
zig build run-full-assessment
zig build run-seakeeping

# Full primitive sweep
zig build test-all

# Intelligence
python tools/agent/harness.py --workflow box_barge --spec examples/agent_spec.json
python tools/agent/harness.py --workflow seakeeping
python tools/oracle/yard_seakeeping_oracle.py
python tools/dataset/generate_seakeeping.py --samples 200 --output tools/dataset/out/seakeeping_train.jsonl
python tools/gap_audit/gap_audit_seakeeping.py --dataset tools/dataset/out/seakeeping_eval.jsonl --baseline naive

# Gap audit (post fine-tune)
python tools/gap_audit/gap_audit.py --model qwen2.5-coder:1.5b --n 200
```

---

## Next Sprint (user decides scope)

1. Ship trim/damage or resistance/propulsion workflow
2. Complete fine-tune loop → post-FT gap audit
3. Deep internals pass: fossen nonlinear, csr core, seakeeping benchmark hull
4. Root CI matrix + benchmark fixtures
5. Agent harness → Zig Bean / local swarm integration