# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `holtrop.c3Coefficient`, `c2Coefficient`, `c4Coefficient`,
  `c7Coefficient` regression.
- `holtrop.BowShape` enum with five Holtrop 1988 shapes.
- `area.ellipseAreaM2`, `immersionFactorPB`, `bulbFroudeNumber`.
- `resistance.bulbResistanceN`, `bulbResistanceFromGeometry`,
  `bulbResistanceRatio`.
- 32-test unit suite including Holtrop coefficient closed forms,
  three-branch c_7, ellipse area + P_B + Fn_i geometry, Aframax-
  class worked R_B, A_BT^1.5 and rho g and Fn_i shape scaling,
  exp(-3/P_B^2) decay across regimes, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

c_4 Table II values flagged `claimed`; regression logic
`unit-tested`.
