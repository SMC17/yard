# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `sfoc.fitThreePoint` exact three-point quadratic fit.
- `sfoc.evaluateSfoc`, `engineLoadKw`, `fuelMassFlowKgPerHr`.
- `nox.NoxTier` enum, `weightedLimitGPerKwh` per MARPOL Annex VI
  Reg. 13.
- `nox.verdict` pass / fail.
- 19-test unit suite including exact three-point recovery,
  parabolic minimum, linear-case zero curvature, three-tier
  ordering, and rpm-plateau verification.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
