# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `fossen.State` and `fossen.Parameters` typed structs.
- `fossen.rk4Step` linearized 6-DOF RK4 integrator.
- 11-test unit suite including zero-in-zero-out invariant, surge
  step-response convergence, heave restoring + damping, decoupled
  channel verification, roll natural-period damping, and impulsive
  limit.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
