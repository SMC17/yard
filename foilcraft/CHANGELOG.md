# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `foil.liftN` 0.5 rho V^2 S C_L.
- `foil.takeoffSpeedMPerS` sqrt(2 W / (rho S C_L)).
- `foil.cavitationOnsetSpeedMPerS` sqrt((p0-pv) / (0.5 rho |Cp|)).
- `foil.cavitationVerdict` sub_cavitating / cavitating.
- `foil.e_surface_piercing`, `e_fully_submerged_default`.
- `foil.liftToDragRatio` C_L / (C_D0 + C_L^2 / (pi AR e)).
- 14-test unit suite including V^2 lift, sqrt(W) take-off scaling,
  cavitation-onset closed form, span-efficiency ordering, and
  typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
