# Status

yard-roro-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `deck_load.apparentWeightN` | `unit-tested` | m g at rest; m (g + a_v) under accel; zero at free-fall |
| `deck_load.lateralLashingForceN` | `unit-tested` | zero at phi=0, a_h=0; m g/2 at 30 deg; linear in mass |
| `deck_load.apparentGravityTiltRad` | `unit-tested` | zero at rest; 30 deg pure-roll case |
| `deck_load.tippingAngleRad` | `unit-tested` | pi/4 at b/h = 2; atan(0.1) at b/h = 0.2 |
| `deck_load.tippingVerdict` | `unit-tested` | inclusive < boundary pass |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `16/16 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: instantaneous force kernel only; the
  kernel does not claim to integrate over a sea state. Caller
  composes with `yard-rao-spectrum-zig` for design accelerations.
- Type-II missed risk guard: typed-error rejection for zero mass,
  roll angle outside +/- pi/2.
- Type-III category guard: deck-load primitive only; not a tyre-
  friction lateral-slip evaluator; not a multi-axle load
  distribution model; not a fire-class compliance gate.

## What is not covered (v0.0.0)

- Stochastic seakeeping convolution.
- Tyre-friction / lateral-slip threshold.
- Multi-axle / articulated trailer.
- Green-water deck flooding.
- IMO A.581 catalog ingestion.

## Composition

- Input `a_v`, `a_h` from `yard-rao-spectrum-zig` significant
  acceleration amplitude.
- Input `phi` from `yard-stir-zig` residual roll envelope or
  short-term roll RAO.
- Output `F_h` feeds lashing system design at a chosen design-load
  fraction.
