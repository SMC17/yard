# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `azipod.resolveSteeringForce`, `advanceVelocity`,
  `sideForceRatio`.
- `azipod.Components` typed struct.
- `waterjet.netThrustN`, `propulsiveEfficiency`, `idealJetPowerW`.
- 20-test unit suite including cardinal-direction decompositions,
  momentum-conservation closed forms, efficiency limit cases, and
  typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
