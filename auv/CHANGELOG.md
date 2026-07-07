# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `hydrodynamics.reynoldsNumber`, `schlichtingCF`, `ittc57CF`,
  `totalDragN`.
- `depth_control.pdControlLawRad`, `steadyStateVerticalVelocityMPerS`,
  `depthErrorTimeConstantS`.
- `endurance.propulsionPowerW`, `enduranceHr`, `rangeKm`,
  `optimalCruiseSpeedMPerS`.
- `glider.glideAngleRad`, `glideSpeedMPerS`,
  `horizontalRangePerLegM`, `verticalRateMPerS`.
- 49-test unit suite covering Re scaling, Schlichting decay,
  PD-clamping, D-term opposes descent, propulsion power
  inversely proportional to eta, range scales linearly with V,
  optimal cruise cube-root, glide angle for L/D = 30 ~ 1.9 deg,
  and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
