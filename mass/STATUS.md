# Status

yard-mass-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `e26.Criticality` | `unit-tested` | Ordering critical > essential > non_essential via @intFromEnum |
| `e26.evaluateCBS` | `unit-tested` | Non-essential CBS sees 1 control; essential CBS missing risk_assessment fails E26-ID-2 with missing list correctly populated; critical CBS sees all 8 controls; critical missing backup fails E26-PR-2 + E26-RC-1; output buffer-size rejection; essential CBS with full evidence passes |
| `e26.default_controls` | `unit-tested` | Used in all evaluation tests; 8-control representative set across all 5 capability domains |

## Coverage caveat

The `default_controls` slice is a representative encoding of UR E26
shape, not a certified reproduction of the IACS rule catalog. Real
deployments should load the authoritative control set from the IACS
publication. Proof level for that catalog: `claimed` until externally
verified.

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `9/9 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: the included control set is explicitly
  flagged as a representative shape, not a certified catalog. Real
  compliance against UR E26 / UR E27 requires the full IACS catalog.
- Type-II missed risk guard: explicit error variant for
  buffer-size mismatch. The harness does not silently truncate.
- Type-III category guard: structural compliance harness; not a
  threat-model generator, not a risk-quantification engine, not
  a penetration-test scheduler.

## What is not covered (v0.0.0)

- Full IACS UR E26 / UR E27 control catalog.
- YAML / JSON config loader for controls.
- Equipment-type-approval registry (UR E27 manufacturer side).
- DNV / ABS / LR class-notation cross-walks.
- Quantitative risk scoring.
- Per-control evidence content validation (e.g., parsing an
  asset-register XML).

## Validation against codex substrate

Formulation traces to
`~/codex/concepts/iacs-ur-e26-cyber-resilience-of-ships.md` and
`~/codex/concepts/iacs-ur-e27-cyber-resilience-on-board-systems.md`.
