# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `cummins.retardationFunctionAtT` inverse cosine transform of
  B(omega) via trapezoidal quadrature.
- `cummins.buildRetardationArray` populates K on a t grid.
- `cummins.addedMassInfinity` Ogilvie 1964 sine-integral identity.
- `cummins.cumminsStep` forward-Euler single-DOF Cummins step.
- 12-test unit suite including K(0) constant-B closed form, delta-
  bump approximation, A_inf zero-K identity, ballistic / restoring
  / memory step verification, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
