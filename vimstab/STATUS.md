# Status

yard-vimstab-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `container_stack.totalStackMassKg` | `unit-tested` | sum of three 20-t tiers = 60 t |
| `container_stack.lateralAccelerationMPS2` | `unit-tested` | g/2 at 30 deg; zero at rest; a_y direct passthrough |
| `container_stack.lateralForceN` | `unit-tested` | 180 kN at 60 t / 3 m/s^2; linear in mass |
| `container_stack.rackingDeflectionM` | `unit-tested` | 18 mm at F=180 kN, k=10 MN/m; inverse-stiffness scaling |
| `container_stack.deflectionVerdict` | `unit-tested` | <= boundary inclusive pass |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `15/15 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: simplified MSC.252(83) screening only;
  the kernel does not claim to compute per-tier corner-post stress
  or twistlock pull-out load.
- Type-II missed risk guard: typed-error rejection for zero
  stiffness, roll outside +/- pi/2, empty tier list, non-positive
  tier mass.
- Type-III category guard: lateral-load screening kernel only; not
  a CSC plate / inspection-cycle gate; not a dynamic-amplification
  engine; not a SOLAS Ch. VI / VII compliance ledger.

## What is not covered (v0.0.0)

- Per-tier bending-moment distribution.
- CSC plate / inspection-cycle gate.
- Transient slamming / dynamic-amplification factor.
- Twistlock / lashing-bar stiffness regression.
- Multi-stack interaction across bays.
- SOLAS Ch. VI / VII / CSS Code companion.

## Composition

- Input `phi` from `yard-stir-zig` parametric-roll or dead-ship
  amplitude.
- Input `a_y_cg` from `yard-rao-spectrum-zig` significant lateral
  acceleration.
- Input `k_total` from twistlock / lashing-bar / corner-post
  combined stiffness; consider a downstream library that builds
  this from per-element values.
