# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `coupled.Complex` add/sub/mul/div/abs.
- `coupled.solveRAO` 3-DOF complex impedance solver with Gauss
  elimination and partial pivoting.
- `coupled.raoMagnitudes` per-DOF response modulus.
- 12-test unit suite including 1-DOF decoupling, identity impedance,
  off-diagonal coupling, low/high-omega limits, resonance peak, and
  singular-matrix detection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
