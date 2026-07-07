# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `end_launch.slidingAccelerationMPS2` declivity / friction.
- `end_launch.wayEndVelocityMPerS` sqrt(2 a L).
- `end_launch.wayEndKineticEnergyJ` 0.5 m v^2.
- `end_launch.velocityFromGeometry` composer.
- `pivoting.buoyancyAtImmersionN`, `sternLiftedOff`,
  `forwardCradleReactionN`.
- `side_launch.waterContactVelocityMPerS` sqrt(2 g H).
- `side_launch.maximumHeelAngleRad` sqrt(v^2 / (g GM)).
- `side_launch.maxHeelFromSlipway`, `heelVerdict`.
- 34-test unit suite including 1:18-slipway closed form, sqrt(L)
  way-end scaling, 5000 t kinetic energy, lever-rule cradle reaction,
  side-launch sqrt(H) contact velocity, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
