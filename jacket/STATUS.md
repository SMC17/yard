# Status

yard-jacket-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `morison.forcePerLengthNM` | `unit-tested` | drag + inertia composition match; sign preservation |
| `morison.forceUniformN` | `unit-tested` | f * L closed form |
| `morison.dragOnlyNM` | `unit-tested` | u^2 scaling |
| `morison.inertiaOnlyNM` | `unit-tested` | du/dt linear; D^2 scaling |
| `airy.waveNumberMInv` | `unit-tested` | deep-water k = omega^2/g; shallow-water k = omega/sqrt(g h) |
| `airy.horizontalVelocityMPerS` | `unit-tested` | crest = H omega / 2 deep water; trough = -crest; decays with z |
| `airy.horizontalAccelerationMPerS2` | `unit-tested` | leads velocity by pi/2 |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `18/18 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: linear Airy regime only; the kernel does
  not claim accuracy in steep / breaking wave conditions where
  stretched (Wheeler / Chakrabarti) kinematics are required.
- Type-II missed risk guard: typed-error rejection for non-positive
  density, coefficient, length, depth; depth-below-surface bound
  checked against water depth.
- Type-III category guard: load-input kernel only; not a global FE
  solver; not a partial-factor / reliability engine; not a diffraction
  / radiation calculator for large-volume bodies.

## What is not covered (v0.0.0)

- Stretched / nonlinear Stokes kinematics.
- Diffraction / radiation effects.
- Member-flexibility dynamic amplification.
- Multi-member shadowing.
- Partial-factor / reliability design.
- Global jacket FE.

## Composition

- Airy kinematics outputs feed `morison.forcePerLengthNM` along the
  member.
- Per-segment Morison force composes externally to a global jacket
  static / quasi-static FE solver.
- Composes with `yard-pipeline-zig` Morison module via the same
  C_D / C_M / D inputs at the seabed.
