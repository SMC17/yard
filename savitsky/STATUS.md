# Status

yard-savitsky-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `savitsky.speedCoefficient` | `unit-tested` | V / sqrt(g B) closed form |
| `savitsky.flatPlateLiftCoefficient` | `unit-tested` | manual expansion match at tau=4, lambda=2, C_V=4; monotone in tau and 1/C_V |
| `savitsky.veeBottomLiftCoefficient` | `unit-tested` | beta=0 equals C_L0; beta=20 gives 0.0673554 from 0.10 to 1e-5; clamp at degenerate |
| `savitsky.hydrodynamicLiftN` | `unit-tested` | 0.5 rho V^2 B^2 C_L closed form to 1e-6 |
| `savitsky.solveTrimDeg` | `unit-tested` | bisection inverse reproduces 98.1 kN within 100 N |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `14/14 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: range-gating to the Savitsky-validated
  domain 2 deg <= tau <= 15 deg and 1 <= lambda <= 4 prevents
  silent extrapolation beyond the empirical fit. Inputs outside that
  range return typed errors rather than a fabricated coefficient.
- Type-II missed risk guard: deadrise gate 0 <= beta <= 30 deg
  protects against unphysical / unfit regimes.
- Type-III category guard: lift-only kernel; not a resistance
  predictor; not a wave-response engine; not a six-DOF planing-craft
  simulator.

## What is not covered (v0.0.0)

- Frictional drag and total resistance (compose with
  `yard-resistance-zig`).
- Trim moment equilibrium with shaft thrust line.
- Spray-rail / chine-strip / step / interceptor corrections.
- Sea-state / irregular-wave response.
- Deep-vee (beta > 30 deg) regime.
- Super-planing (C_V > ~10) regime.

## Composition

- Output `C_Lbeta` feeds the lift side of a planing-hull resistance
  loop where the friction side composes with `yard-resistance-zig`
  on a wetted area scaled by lambda B.
- `solveTrimDeg` is the planing-hull analogue of an Archimedes
  weight-displacement solve.
