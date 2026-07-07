# Status

yard-sloshing-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `rectangular.waveNumberAntisymmetric` | `unit-tested` | k_0 = pi/L; k_1 = 3 pi/L |
| `rectangular.waveNumberSymmetric` | `unit-tested` | k_1 = 2 pi/L; k_2 = 4 pi/L; n=0 rejected |
| `rectangular.naturalAngularFrequency` | `unit-tested` | sqrt(g k tanh(k h)) closed form |
| `rectangular.naturalPeriodSec` | `unit-tested` | 2 pi / omega closed form |
| `rectangular.fundamentalAntisymmetricRectangular` | `unit-tested` | Faltinsen-Timokha 4.3.1 worked example omega_1 = 3.768 to 0.01 |
| `rectangular.deepWaterLimitOmega` | `unit-tested` | matches finite-depth at k h = 31.4 (k=pi/10, h=100) |
| `rectangular.shallowWaterLimitOmega` | `unit-tested` | relative error < 1e-4 at k h ~ 1.6e-3 |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `12/12 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: linear potential-flow regime only; the
  kernel does not claim accuracy for high-amplitude sloshing where
  the multimodal nonlinear analysis becomes load-bearing. The
  shallow-water limit caveat is documented and exercised.
- Type-II missed risk guard: symmetric mode n = 0 rejected
  (degenerate / non-physical); non-positive length / depth / gravity
  rejected with typed errors.
- Type-III category guard: eigenfrequency kernel only; not an
  impact-pressure predictor; not a tank-vessel coupled motion
  solver; not a viscous-damping model; not a stratified / two-layer
  sloshing engine.

## What is not covered (v0.0.0)

- Nonlinear multimodal analysis.
- Prismatic / membrane LNG-tank shapes (Type B, Type C, MOSS).
- Impact-pressure prediction.
- Coupled tank-vessel sloshing.
- Viscous damping.
- Two-layer / stratified sloshing.

## Composition

- Output `omega_1` couples to `yard-coupled-motions-zig` as a tuned-
  mass resonance band that should not coincide with vessel sway /
  roll natural periods.
- For LNG-cargo applications, compose externally with the carrier's
  classification-society sloshing-pressure procedure.
