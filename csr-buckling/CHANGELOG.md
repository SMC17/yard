# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `plate.bucklingCoefficient` for SS / clamped plates under uniaxial
  compression or shear.
- `plate.elasticCriticalStressPa` for the classical thin-plate
  sigma_cr formula.
- `plate.johnsonReducedStressPa` CSR Section 8.2.2 inelastic
  reduction.
- `column.effectiveLengthFactor` for pinned-pinned, fixed-pinned,
  fixed-fixed, fixed-free.
- `column.eulerCriticalLoadN` and `column.eulerCriticalStressPa`.
- `column.slendernessRatio` lambda = mu L / sqrt(I/A).
- `column.eulerCriticalStressFromLambdaPa` for direct slenderness.
- 24-test unit suite including closed-form k coefficients, scaling
  laws, Johnson reduction limits, and end-condition ratios.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
