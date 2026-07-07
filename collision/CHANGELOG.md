# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `minorsky.resistanceFactorM3` volumetric damage proxy.
- `minorsky.absorbedEnergyMJ` energy regression 47.1 R_T + 32.7.
- `kinetic.mu_minorsky_struck_lateral` and
  `mu_minorsky_striking_longitudinal` constants.
- `kinetic.effectiveMassKg`, `kineticEnergyJ`,
  `kineticEnergyWithAddedMassJ`.
- `kinetic.rightAngleAbsorbedEnergyJ` perfectly plastic two-body
  impact energy partition.
- 20-test unit suite including R_T sum, intercept/slope of energy
  regression, added-mass scaling, and asymmetric-mass limits.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
