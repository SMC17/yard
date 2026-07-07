# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `lindqvist.Geometry`, `lindqvist.IceProperties` typed structs.
- `lindqvist.crushingResistanceN`, `bendingResistanceN`,
  `submersionResistanceN`.
- `lindqvist.totalResistance` with `1 + 1.4 Fn_h` speed-dependent
  bending correction.
- `lindqvist.ResistanceBreakdown` result struct.
- 12-test unit suite including closed-form crushing, h^2 scaling,
  positivity, density-difference linearity, zero-speed totalling,
  and finite-speed correction.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

Crushing form uses compact 0.5 sigma_f h^2 tan(alpha); full
hull-dependent Lindqvist expression deferred.
