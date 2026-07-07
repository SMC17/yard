# Status

yard-stir-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `dead_ship.staticHeelAngleSmallAngleRad` | `unit-tested` | M_wind / (Delta GM g) closed form; linear scaling |
| `dead_ship.residualRollAngleRad` | `unit-tested` | 0.087 + 1.7 * 0.349 = 0.681 rad worked example |
| `dead_ship.verdict` | `unit-tested` | < boundary inclusion |
| `parametric.encounterFrequencyRps` | `unit-tested` | head seas mu = pi gives omega_w + k V; following mu = 0 gives omega_w - k V |
| `parametric.naturalRollFrequencyRps` | `unit-tested` | sqrt(g GM) / k_xx closed form |
| `parametric.principalMathieuRatio` | `unit-tested` | R = 1.0 at omega_e = 2 omega_phi |
| `parametric.verdict` | `unit-tested` | band [0.85, 1.15] fails; outside passes |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `20/20 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: VL1 envelopes only; VL2 / direct
  simulation are explicitly listed under "what is not covered".
  Small-angle linear GZ regime; the kernel does not claim accuracy
  beyond the deck-edge immersion / downflooding angle.
- Type-II missed risk guard: typed-error rejection for negative
  moment, non-positive GM / k_xx / V, negative phi_m.
- Type-III category guard: VL1 screening kernel only; not a VL2
  probabilistic engine; not a time-domain integrator (compose with
  `yard-fossen-6dof-zig`); not a surf-riding / broaching predictor;
  not an excessive-acceleration / pure-loss-of-stability calculator.

## What is not covered (v0.0.0)

- VL2 probabilistic check.
- Direct time-domain simulation.
- Surf-riding / broaching VL1.
- Excessive-acceleration / pure-loss-of-stability VL1.
- Nonlinear GZ-crossing.
- Roll-pitch-heave coupling.

## Composition

- Inputs Delta, GM, k_xx from `yard-stability-zig` and
  `yard-hydro-zig`.
- Output phi_1 against the deck-edge / downflooding angle from
  `yard-stability-zig::IS Code Part A 2.2 worked example`.
- Composes externally with the classification-society VL2 procedure
  for the second-tier gate.
