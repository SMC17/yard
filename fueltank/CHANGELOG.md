# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `reg_12a.capacity_threshold_m3` 600 m^3.
- `reg_12a.requiredSideDistanceM` clamped 0.4 + 2.4 C / 20000 m.
- `reg_12a.requiredDoubleBottomHeightM` clamped B / 20 m.
- `reg_12a.complianceVerdict` pass / fail vs required.
- 15-test unit suite including threshold zero, 1.0 m lower clamp,
  1.6 m at C=10k m^3, 2.0 m upper clamp, B-driven double-bottom
  clamp, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
