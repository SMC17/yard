# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `morison.forcePerLengthNM` combined drag + inertia per unit length.
- `morison.forceUniformN` integrate over uniform segment.
- `morison.dragOnlyNM`, `inertiaOnlyNM` limits.
- `airy.waveNumberMInv` Newton-iterated dispersion solve.
- `airy.horizontalVelocityMPerS`, `horizontalAccelerationMPerS2`
  linear-wave kinematics.
- 18-test unit suite including drag + inertia composition, signed
  drag, dispersion limits, MSL crest velocity, and phase-quadrature
  acceleration.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
