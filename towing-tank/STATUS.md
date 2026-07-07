# Status

yard-towing-tank-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `prohaska.fit` | `unit-tested` | exact synthetic recovery (1e-9 on intercept/slope, R^2 = 1) for `(1+k)=1.15, a=0.5`; noisy R^2 > 0.99; zero-slope viscous regime; Fn=0 anchor recovery |
| `self_prop.thrustDeductionFactor` | `unit-tested` | t = 0.2 for R=800, T=1000; t = 1 at R=0; t = 0 at R=T |
| `self_prop.taylorWakeFraction` | `unit-tested` | w = 0.3 at V_a/V_m = 0.7 |
| `self_prop.hullEfficiency` | `unit-tested` | (1-0.2)/(1-0.3) = 8/7 closed form |
| `self_prop.analyzeSOP` | `unit-tested` | composite of three checks; V_a > V_m negative-wake regime numerically consistent |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `20/20 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: `prohaska.fit` returns `DegenerateData`
  when the X-axis variance is zero rather than silently producing
  an undefined slope. Zero / non-positive C_F is rejected with a
  typed error. SOP analysis rejects non-positive thrust, negative
  resistance, non-positive speeds, and t >= 1.
- Type-II missed risk guard: R^2 reported alongside the regression
  so callers cannot use a `(1 + k)` value from a non-linear data set
  without noticing.
- Type-III category guard: data-reduction kernel only; not a
  resistance predictor (use `yard-resistance-zig`); not a powering
  extrapolator (use `yard-ittc78-zig`); not a propeller open-water
  fit (use `yard-propulsion-zig`).

## What is not covered (v0.0.0)

- Automatic Fn-cutoff selection.
- Holtrop-Mennen form-factor regression.
- Open-water K_T / K_Q curve fitting.
- Ship-scale extrapolation.
- Uncertainty bands.
- Time-series tank-data ingest (caller supplies block-mean values).

## Composition

- Output `(1 + k)` from `prohaska.fit` feeds the form-factor input
  to `yard-resistance-zig::ittc57::C_F_with_form_factor` and the
  scaling step in `yard-ittc78-zig::extrapolate`.
- Output `t`, `w_T` from `self_prop.analyzeSOP` feeds the propulsive-
  coefficient inputs of `yard-ittc78-zig::PropulsionFactors`.
