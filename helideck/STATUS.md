# Status

yard-helideck-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `motion.limitsForClass` | `claimed` | values per CAP 437 + MSC.1/Circ.1378 + operator MEL convention; supplier-specific MEL must be verified |
| `motion.lateralAccelerationFromRollMPS2` | `unit-tested` | phi_dd * h closed form; linear h scaling |
| `motion.inclinationDeg` | `unit-tested` | 3-4-5 Pythagorean closed form |
| `motion.envelopeVerdict` | `unit-tested` | pass / fail across all four limit dimensions; class-ordering test |

## Coverage caveat

Motion-limit values transcribed from publicly cited offshore-
helideck operating guidance. For regulatory submission caller
must verify against the helicopter-operator's individual MEL.

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `14/14 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: motion-limit table flagged `claimed`;
  the kernel does not substitute for operator-specific MEL.
- Type-II missed risk guard: typed-error rejection for negative
  pitch / roll / heave_rate, zero deck CG height. Combined
  inclination is computed alongside the per-axis check so the
  envelope cannot silently pass at a too-aggressive combined attitude.
- Type-III category guard: motion envelope only; not a turbulence /
  downwash analyser; not an EOD net-positive-buoyancy gate; not a
  perimeter / marking geometry checker.

## What is not covered (v0.0.0)

- Aircraft-specific MEL overrides.
- Probability-of-operation cumulative distribution.
- Deck-edge airflow / turbulence envelope.
- EOD net-positive-buoyancy clearance.
- Helideck markings, T-D / RIM geometry.
- Friction-coefficient verification.

## Composition

- Input pitch and roll from `yard-seakeeping-zig` significant
  amplitude + `yard-strip-theory-zig` RAO.
- Input heave-rate from `yard-rao-spectrum-zig` significant
  velocity amplitude.
- Deck CG height `h` from the vessel general-arrangement.
