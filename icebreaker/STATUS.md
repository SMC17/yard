# Status

yard-icebreaker-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `lindqvist.crushingResistanceN` | `unit-tested` | 0.5 sigma_f h^2 tan(alpha) closed form to 1 N; sigma_f x 1, h x 2 -> ratio 4 |
| `lindqvist.bendingResistanceN` | `unit-tested` | positive; below 1e8 N order-of-magnitude ceiling |
| `lindqvist.submersionResistanceN` | `unit-tested` | positive; (rho_w - rho_i) linear scaling |
| `lindqvist.totalResistance` | `unit-tested` | V=0 equals R_c+R_b+R_s; speed correction raises R_b only |

## Coverage caveat

The crushing formula uses the compact `0.5 sigma_f h^2 tan(alpha)`
form rather than the full hull-dependent Lindqvist expression; the
bending and submersion expressions follow the published simplified
forms. For Polar-Code-grade design submission caller should
compose with the classification-society procedure.

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `12/12 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: the `crushingResistanceN` form is the
  compact Erikstad / Riska summary, not the full Lindqvist hull-
  dependent expression. Caller must compose with the full Lindqvist
  paper or a classification-society procedure for Polar Code work.
- Type-II missed risk guard: typed-error rejection for zero ice
  thickness, negative speed, alpha / phi / psi outside (0, 90) deg,
  rho_i >= rho_w. The kernel does not silently produce a negative or
  nonsensical resistance.
- Type-III category guard: level-ice resistance kernel only; not a
  managed-channel / brash-ice predictor; not a ridge-load model;
  not an impact-load engine; not a probabilistic POAC envelope.

## What is not covered (v0.0.0)

- Brash-ice / channel reduction factor.
- Ridge-load model.
- Transient impact loads.
- POAC probabilistic envelope.
- Multi-layer ice.
- Polar Code class-notation cross-walks.

## Composition

- Output `R_total_n` couples to `yard-ittc78-zig` SHP chain by
  adding `R_ice` to the open-water resistance at the same speed.
- Compose with `yard-eedi-zig` for the EEDI ice-class adjustment
  factor caller chain.
