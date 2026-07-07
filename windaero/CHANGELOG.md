# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `blendermann.rho_air_standard = 1.225` kg/m^3.
- `blendermann.ShipType` enum (Container, Tanker, Bulk, Passenger,
  Generic).
- `blendermann.peakCoefficients` ship-type peak C_X / C_Y / C_N.
- `blendermann.longitudinalCoefficient`, `lateralCoefficient`,
  `yawMomentCoefficient` single-mode shapes.
- `blendermann.longitudinalForceN`, `lateralForceN`, `yawMomentNm`.
- 13-test unit suite including cardinal directions, V^2 scaling,
  peak-at-pi/4 yaw moment, ship-type ordering, and typed-error
  rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

Peak coefficient catalogue flagged `claimed`; full Blendermann
multi-mode coefficients deferred.
