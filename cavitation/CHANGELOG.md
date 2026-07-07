# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `burrill.velocityAt07RMPerS`, `localCavitationNumber`,
  `thrustLoadingCoefficient`.
- `burrill.permissibleTauC5Pct` and `permissibleTauC2Pt5Pct`
  power-law fits of the 1943 Burrill chart.
- `burrill.check5Pct` verdict.
- `keller.k_single_screw`, `keller.k_twin_screw`.
- `keller.minimumBladeAreaRatio`.
- 21-test unit suite covering closed-form V_R, sigma_n, tau_c, Burrill
  power-law contours, merchant-propeller Keller worked example, and
  scaling laws.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

Burrill power-law fit coefficients flagged `claimed`; the evaluation
logic itself is `unit-tested`.
