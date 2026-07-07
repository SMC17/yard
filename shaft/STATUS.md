# Status

yard-shaft-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `holzer.holzerResidual` | `unit-tested` | residual = 0 at the analytic two-inertia frequency to 1e-6; sign change between low and high omega |
| `holzer.findNaturalFrequency` | `unit-tested` | two-inertia analytic recovery to 1e-4; three-inertia mode in bracket |
| `shaft_stiffness.polarSolidM4` | `unit-tested` | pi D^4 / 32 closed form; D^4 scaling |
| `shaft_stiffness.polarHollowM4` | `unit-tested` | D_i = 0 reduces to solid |
| `shaft_stiffness.torsionalStiffnessNmPerRad` | `unit-tested` | doubling L halves k |
| `shaft_stiffness.polarMassInertiaSolidKgm2` | `unit-tested` | linear in L |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `19/19 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: Holzer is a free-free undamped lumped-
  inertia method; the kernel does not claim damped-response
  amplitudes. Bisection inside `findNaturalFrequency` returns
  `Error.NoConvergence` if the bracket does not contain a sign
  change rather than silently producing a spurious frequency.
- Type-II missed risk guard: typed-error rejection for insufficient
  stations, unequal-length arrays, non-positive inertia / stiffness
  / omega / diameter / length, invalid hollow geometry.
- Type-III category guard: torsional vibration only; not a bending
  / whirl analyser; not a damped-response solver; not a fatigue-
  life predictor (compose with `yard-csr-fatigue-zig`).

## What is not covered (v0.0.0)

- Damped-vibration response.
- Multi-mode automatic bracketing.
- Transfer-matrix non-uniform / branched chains.
- Bending whirl / lateral vibration.
- Propeller-water added-mass coupling.
- Torsional fatigue life.

## Composition

- Inertia inputs J for the propeller, gearbox, intermediate / line
  shafts feed the Holzer chain.
- Stiffness inputs k from `torsionalStiffnessNmPerRad` close the
  shaft-segment geometry to the chain.
- Output `omega_n` couples to the engine firing frequency in
  `yard-engine-zig` to identify resonance avoidance.
