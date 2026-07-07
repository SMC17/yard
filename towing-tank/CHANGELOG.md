# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `prohaska.Result` carrying `one_plus_k`, `slope_a`, `r_squared`.
- `prohaska.fit` linear regression on `(Fn^4 / C_F, C_T / C_F)`.
- `self_prop.thrustDeductionFactor` t = 1 - R_T / T.
- `self_prop.taylorWakeFraction` w_T = 1 - V_a / V_m.
- `self_prop.hullEfficiency` eta_H = (1 - t) / (1 - w_T).
- `self_prop.SOPInputs` / `self_prop.SOPResult` typed structs.
- `self_prop.analyzeSOP` composer.
- 20-test unit suite including exact synthetic recovery, noisy
  recovery R^2 floor, viscous-regime zero-slope check, Fn=0 anchor
  fix, and typed-error rejection of unequal length, insufficient
  points, non-positive C_F, degenerate variance, non-positive
  thrust, negative resistance, non-positive speeds, and t >= 1.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
