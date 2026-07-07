# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `allocation.Thruster`, `allocation.Demand` typed structs.
- `allocation.allocate` minimum-energy thrust allocation.
- `allocation.closingResidual` diagnostic.
- `allocation.max_thrusters = 8` stack-buffer ceiling.
- Singular-configuration detection via 1e-18 determinant threshold.
- 9-test unit suite including bow + stern three-thruster, pure
  surge / pure yaw / pure sway, four-thruster redundant DP-2 style,
  and degenerate colinear rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
