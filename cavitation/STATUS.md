# Status

yard-cavitation-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `burrill.velocityAt07RMPerS` | `unit-tested` | zero-advance reduces to 0.7 pi n D; quadrature combination |
| `burrill.localCavitationNumber` | `unit-tested` | closed form to 1e-12 |
| `burrill.thrustLoadingCoefficient` | `unit-tested` | scales linearly in T |
| `burrill.permissibleTauC5Pct` | `claimed` | power-law fit a=0.45, b=0.4 derived as a least-squares interpolant of the published Burrill 1943 5% contour; no independent re-reading of the original chart |
| `burrill.permissibleTauC2Pt5Pct` | `claimed` | same caveat; 2.5% fit a=0.34, b=0.4 |
| `burrill.check5Pct` | `unit-tested` | low/high tau verdict consistency |
| `keller.minimumBladeAreaRatio` | `unit-tested` | 4-blade merchant example 0.7556; linear in T; inverse D^2; monotone Z; K offset |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `21/21 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: Burrill chart fit coefficients flagged
  `claimed` until re-verified against an independent source. The
  evaluation logic and Keller formula are `unit-tested`.
- Type-II missed risk guard: blade-count gating [2, 7] prevents
  silent extrapolation to non-physical Z; pressure differential
  must be positive (cavitating regime requires p_0 > p_v).
- Type-III category guard: chart-based screening kernel only; not a
  cavity-shape solver; not a noise / URN predictor; not an
  erosion-rate model.

## What is not covered (v0.0.0)

- Tip-vortex / sheet-cavity volume model.
- Erosion prediction.
- Underwater radiated noise.
- Non-uniform wake / inflow field.
- High-skew propeller correction.
- 3D BEM / RANS cavity-shape solve.

## Composition

- Composes with `yard-propulsion-zig` (Wageningen B-series): tau_c
  uses the same T as the K_T output; sigma_n uses the same V_R as the
  J = V_a / (n D) input.
- Composes with `yard-ittc78-zig`: same operating point at SOP.
