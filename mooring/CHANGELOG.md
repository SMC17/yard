# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `catenary.catenaryParameterM` a = H / w.
- `catenary.catenaryY` y(x) = a (cosh(x/a) - 1).
- `catenary.arcLengthM` s(x) = a sinh(x/a).
- `catenary.tensionAtXN` T(x) = H cosh(x/a).
- `catenary.verticalForceN` V(x) = H sinh(x/a).
- `catenary.tangentAngleRad` atan(sinh(x/a)).
- `catenary.solveHorizontalForceFromXYN` bisection inverse solver.
- 17-test unit suite including closed-form shape, energy identity
  T = H + w y, V = w s consistency, and inverse-solve four-decade
  range.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
