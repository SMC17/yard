# yard-towing-tank-zig

Proof level: `unit-tested`

yard-towing-tank-zig is a Zig 0.16 model-test data-reduction kernel.
Two modules: `prohaska` extracts the form factor `(1 + k)` and
wave-resistance slope `a` from tabulated low-Froude-number resistance
data via a Prohaska linear regression on the transformed pair
`(Fn^4 / C_F, C_T / C_F)`. `self_prop` extracts thrust-deduction
factor `t`, Taylor wake fraction `w_T`, and hull efficiency `eta_H`
from a single self-propulsion operating point.

## What it does

### Prohaska resistance reduction

- `prohaska.fit(Fn, C_T, C_F)` returns a `Result` containing
  `one_plus_k`, `slope_a`, and `r_squared` of the linear regression
  `C_T / C_F = (1 + k) + a Fn^4 / C_F` (ITTC 7.5-02-02-01).
- Allocator-free; two-pass running sums for the regression and the
  residual sum-of-squares.

### Self-propulsion analysis

- `self_prop.thrustDeductionFactor(R_T, T)` returns `t = 1 - R_T / T`.
- `self_prop.taylorWakeFraction(V_m, V_a)` returns `w_T = 1 - V_a / V_m`.
- `self_prop.hullEfficiency(t, w_T)` returns `eta_H = (1 - t) / (1 - w_T)`.
- `self_prop.analyzeSOP(in)` composes the three steps for a single SOP
  measurement.

## What it is not (v0.0.0)

- No rainflow / wave-by-wave decomposition of tank time histories
  (caller supplies block-mean coefficients).
- No automatic Prohaska Fn-cutoff selection (caller filters to the
  low-Fn band before passing).
- No Holtrop-Mennen form factor regression (caller composes externally
  via `yard-resistance-zig`).
- No open-water curve K_T(J), K_Q(J) extraction (compose externally
  via `yard-propulsion-zig`).
- No ship-scale extrapolation (compose externally via
  `yard-ittc78-zig`).
- No statistical uncertainty bands.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 20/20 tests passed`.

## Public API

```zig
const yard = @import("yard_towing_tank");

// Prohaska form-factor extraction.
const Fn = [_]f64{ 0.10, 0.11, 0.12, 0.13, 0.14, 0.15 };
const CT = [_]f64{ ... };
const CF = [_]f64{ ... };
const r = try yard.prohaska.fit(&Fn, &CT, &CF);
// r.one_plus_k, r.slope_a, r.r_squared

// Self-propulsion at SOP.
const sop = try yard.self_prop.analyzeSOP(.{
    .R_T_model_n = 800.0,
    .T_model_n   = 1000.0,
    .V_m         = 2.0,
    .V_a         = 1.4,
});
// sop.t, sop.w_T, sop.eta_H
```

## Validation

- Synthetic Prohaska data with `(1 + k) = 1.15`, `slope_a = 0.5`,
  `C_F = 0.003`: recovered intercept and slope agree to 1e-9 with
  R^2 = 1.0.
- Mildly noisy synthetic data: R^2 above 0.99 and recovered intercept
  within 1e-2 of truth.
- Purely viscous regime (zero slope): intercept matches `(1 + k)` to
  1e-9.
- Including `Fn = 0` row fixes the intercept at the noise-free
  `C_T / C_F` ratio.
- Thrust deduction at `R_T = 0.8 T` gives `t = 0.2`.
- Wake at `V_a / V_m = 0.7` gives `w_T = 0.3`.
- Hull efficiency `(1 - 0.2) / (1 - 0.3) = 8/7 ~ 1.143` in the
  typical ship range.
- Negative-wake (V_a > V_m) case yields a numerically consistent
  `eta_H < 1 - t`.
- Typed-error rejection for unequal lengths, fewer than three points,
  non-positive `C_F`, zero-variance X data, non-positive thrust /
  speed, negative resistance, `t >= 1`.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- ITTC Recommended Procedure 7.5-02-02-01 (Resistance Tests).
- ITTC Recommended Procedure 7.5-02-03-01.1 (Propulsion Tests).
- Prohaska, C. W. (1966). *A Simple Method for the Evaluation of the
  Form Factor and the Low Speed Wave Resistance*. Proceedings of the
  11th ITTC.
- Molland, A. F., Turnock, S. R., Hudson, D. A. (2017). *Ship
  Resistance and Propulsion*. 2nd ed., Cambridge.

## License

Apache-2.0.
