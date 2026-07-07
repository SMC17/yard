# Status

yard-bow-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `holtrop.c3Coefficient` | `unit-tested` | 0.56 A_BT^1.5 / (B T (0.31 sqrt(A_BT) + T_F - h_B)) closed form |
| `holtrop.c2Coefficient` | `unit-tested` | zero-bulb = 1; monotone decrease in c_3; exp(-1.89 sqrt(c_3)) match |
| `holtrop.c4Coefficient` | `claimed` | Holtrop 1988 Table II values transcribed verbatim |
| `holtrop.c7Coefficient` | `unit-tested` | three-branch coverage narrow / typical / wide |
| `area.ellipseAreaM2` | `unit-tested` | pi at D = 2; linear scaling |
| `area.immersionFactorPB` | `unit-tested` | 0.448 worked example; deeper bulb gives larger P_B |
| `area.bulbFroudeNumber` | `unit-tested` | monotone in V; degenerate geometry rejected |
| `resistance.bulbResistanceN` | `unit-tested` | A_BT^1.5 scaling; Fn_i^3 / (1 + Fn_i^2) shape; rho g linearity; exp(-3/P_B^2) decay |
| `resistance.bulbResistanceFromGeometry` | `unit-tested` | composer reproduces composed call |
| `resistance.bulbResistanceRatio` | `unit-tested` | R_B / R_W closed form |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `32/32 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: c_4 values flagged `claimed` (Holtrop 1988
  Table II); the regression itself is `unit-tested`. The kernel does
  not pretend to compute the bulbous-bow effect via CFD; it implements
  the Holtrop-Mennen empirical regression to its published precision.
- Type-II missed risk guard: typed-error rejection for non-positive
  A_BT / B / T / T_F / V / density, T_F - 1.5 h_B <= 0 (bulb tip
  above waterline + safety margin), and T_F - h_B - 0.25 sqrt(A_BT)
  <= 0 (bulb too close to surface for Fn_i to be defined).
- Type-III category guard: bulbous-bow regression only; not a CFD
  optimiser; not an off-design ballast/heavy correction; not a
  bow-thruster opening drag model; not a breaking-bow-wave engine.

## What is not covered (v0.0.0)

- CFD-derived bulb-shape optimisation.
- Off-design (ballast / heavy) draft correction.
- Bow-thruster opening drag.
- Spray / breaking-bow-wave model.
- CAD-mesh A_BT extraction (caller supplies the integrated area).

## Composition

- `c2`, `c3`, `c4`, `c7` outputs feed the wave-resistance regression
  in `yard-resistance-zig::holtrop_mennen` as multiplicative factors.
- `R_B` from `resistance.bulbResistanceFromGeometry` adds directly
  to the bare-hull wave resistance.
- A_BT from `area.ellipseAreaM2` can be replaced by CAD-mesh
  extraction once a mesher is available.
