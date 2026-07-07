# Status

yard-keel-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `appendage.effectiveAspectRatio` | `unit-tested` | h^2 / S closed form |
| `appendage.liftCoefficient` | `unit-tested` | closed form at alpha = 5 deg, AR = 4; slope = 2 pi AR / (AR + 2); high-AR -> 2 pi |
| `appendage.inducedDragCoefficient` | `unit-tested` | C_L^2 scaling; AR = pi reduction |
| `appendage.sideForceN` | `unit-tested` | V^2 scaling |
| `appendage.inducedDragN` | `unit-tested` | drag-to-lift ratio small at small alpha |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `13/13 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: lifting-line approximation only; the kernel
  does not claim accuracy on stalled / post-separated regimes
  (alpha >= alpha_stall typically 12-15 deg for yacht foils). The
  high-AR limit recovers the thin-airfoil 2 pi slope; very low AR
  (< 0.5) approaches the slender-body limit not covered by this
  expression.
- Type-II missed risk guard: typed-error rejection for zero AR / S /
  V, alpha >= pi/2.
- Type-III category guard: keel + appendage lift / induced-drag
  kernel only; not a VPP solver; not a frictional-drag calculator;
  not a wing-keel / bulb-keel induced-drag reducer; not a
  fluid-structure-interaction model.

## What is not covered (v0.0.0)

- Bulb-keel / wing-keel induced-drag reduction.
- Transverse-cant / canting-keel geometry.
- DSYHS bare-hull regression.
- Sail-trim / VPP coupling.
- Frictional drag.
- FSI keel-flex.

## Composition

- Compose `appendage.sideForceN` with the heeled-sailplan side force
  for force-balance.
- Compose `appendage.inducedDragN` with `yard-resistance-zig`
  frictional + residuary drag for the total resistance.
- For appendage-area sizing, the VPP loop solves for `S` such that
  side-force balance closes at the design heel angle.
