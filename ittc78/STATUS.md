# Status

yard-ittc78-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `chain.extrapolate` | `unit-tested` | Reynolds match independent calculation to f64 round-off; C_F model > C_F ship (Reynolds direction); C_A < 0 at L_s = 1000 m; C_A ~ 0.000479 at L_s = 100 m; P_S = P_D / eta_S; P_E V^3 scaling within 20 percent; C_R = C_T_model - (1+k) C_F_model to f64 round-off |
| `chain.extrapolate` input validation | `unit-tested` | Explicit errors for invalid wake fraction, thrust deduction, non-positive dimensions, Reynolds below ITTC-57 validity |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `12/12 tests pass`.

```
zig build test --summary all
```

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: V^3 scaling test uses a 20 percent tolerance
  because the C_F drift with Reynolds is a real physical effect, not
  measurement noise.
- Type-II missed risk guard: explicit error variants for wake
  fraction outside [0, 0.9], thrust deduction outside [-0.1, 0.5],
  Reynolds below ITTC-57 validity, non-positive dimensions.
- Type-III category guard: this is an extrapolation kernel, not a
  Prohaska-plot fitter, not a propeller selector, not a fuel-
  consumption estimator.

## What is not covered (v0.0.0)

- Prohaska plot (1+k) fitting.
- Self-propulsion test parsing.
- Propeller open-water test parsing.
- Appendage allowance.
- Cavitation analysis.

## Validation against codex substrate

Formulas trace to
`~/codex/concepts/ittc-57-and-ittc-78-extrapolation.md` and
`~/codex/sources/pdfs/ittc/75-02-03-014-performance-powering-prediction.pdf`.
