# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `rcs.flatPlateNormalIncidenceM2`, `sphereGeometricM2`,
  `trihedralCornerReflectorM2`.
- `rcs.radarRangeM`, `gainFromAperture`.
- `rcs.dBsmToM2`, `m2ToDBsm`.
- `weapon.recoilImpulseNs`, `meanRecoilForceN`, `muzzleEnergyJ`.
- `weapon.vlsDeckPressurePa`, `timeToApexS`, `vacuumMaxRangeM`.
- `magazine.QDCategory` IBD/PTRD/IMD/IMD_shielded.
- `magazine.quantityDistanceM`, `maximumCredibleEventKg`,
  `separationVerdict`.
- 42-test unit suite covering RCS scaling laws, radar-range fourth-
  root, recoil + muzzle-energy closed forms, QD cube-root scaling,
  IBD/PTRD/IMD ordering, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
