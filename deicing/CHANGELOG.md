# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `overland.T_freeze_seawater_deg_c = -1.7`.
- `overland.predictorIndex` Overland 1986 PR formula.
- `overland.IcingClass` enum (none, light, moderate, heavy, extreme).
- `overland.classifyByIndex`, `classifyByConditions`.
- `accreted.rho_ice_seawater_spray_kg_per_m3 = 900`.
- `accreted.accretedMassKg`, `accretionRateMperHrForClass`,
  `totalAccretedWeightKg`.
- 22-test unit suite including PR closed form, class boundary
  mapping, accreted weight scaling, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

Class accretion rates flagged `claimed`; per-vessel calibration
deferred.
