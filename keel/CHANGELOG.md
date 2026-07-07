# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `appendage.effectiveAspectRatio` h^2 / S.
- `appendage.liftCoefficient` 2 pi alpha AR / (AR + 2).
- `appendage.inducedDragCoefficient` C_L^2 / (pi AR).
- `appendage.sideForceN`, `inducedDragN`.
- 13-test unit suite including closed-form lift coefficient, high-
  AR thin-airfoil limit, C_L^2 induced-drag scaling, V^2 force
  scaling, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
