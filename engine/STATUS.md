# Status

yard-engine-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `sfoc.fitThreePoint` | `unit-tested` | exact recovery at the three input points; symmetric parabola min at x=75; linear case c=0 |
| `sfoc.evaluateSfoc` | `unit-tested` | quadratic evaluation; range gate [0, 110] |
| `sfoc.engineLoadKw` | `unit-tested` | 75 % of 20000 = 15000 kW |
| `sfoc.fuelMassFlowKgPerHr` | `unit-tested` | 170 g/kWh * 15000 kW / 1000 = 2550 kg/h |
| `nox.weightedLimitGPerKwh` | `unit-tested` | low-speed plateau, high-speed plateau, middle power law for all three tiers; Tier I > II > III ordering at 720 rpm |
| `nox.verdict` | `unit-tested` | <= boundary inclusion |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `19/19 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: SFOC quadratic is exact only at the three
  input points; the kernel does not claim sub-percent fit between
  arbitrary multi-point datasets. Range gate clips to [0, 110] %
  MCR.
- Type-II missed risk guard: typed-error rejection for non-positive
  SFOC, non-positive engine speed / MCR, load outside [0, 110].
- Type-III category guard: SFOC + NOx limit kernel only; not a
  thermodynamic-cycle engine simulator; not a turbocharger lag
  model; not a certified test-cycle weighting calculator; not a SOx
  / PM compliance engine.

## What is not covered (v0.0.0)

- Multi-point SFOC regression.
- Part-load efficiency-island map.
- Transient turbocharger response.
- E2 / E3 / D2 certified test-cycle weighting.
- SFOC -> CO2 crosswalk (compose with `yard-eedi-zig`).
- SOx limits (MARPOL Annex VI Reg. 14).

## Composition

- SFOC quadratic feeds `yard-eedi-zig::Engine.SFC_g_per_kwh` at the
  required engine operating point.
- NOx limit verdict integrates with the EIAPP / EAPP certification
  workflow for the same rated speed.
- Rated engine speed couples to `yard-shaft-zig::findNaturalFrequency`
  for torsional-resonance avoidance.
