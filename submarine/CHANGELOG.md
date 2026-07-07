# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `pressure_hull.hydrostaticPressurePa`, `hoopStressPa`,
  `yieldCollapsePressurePa`, `vonMisesCriticalN`.
- `pressure_hull.crushDepthM`, `operatingDepthM`.
- `dive.seawaterDensityAtDepthKgPerM3`, `netBuoyancyN`,
  `quasiSteadyAscentMPerS`, `deepDiveDecoStopMin`.
- `ballast.mbtCapacityM3`, `reserveBuoyancyFraction`,
  `trimTransferMassKg`, `compensatingWaterVolumeM3`.
- 40-test unit suite covering p = rho g d, hoop sigma p R / t,
  yield-collapse, von Mises positive for typical submarine inputs,
  crush depth + 1.5 / 2.0 SF, density-with-depth, net buoyancy
  sign cases, ascent sqrt(F) scaling, MBT capacity linear in delta
  W, trim transfer lever rule, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
