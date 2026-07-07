# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `rectangular.waveNumberAntisymmetric`, `waveNumberSymmetric`.
- `rectangular.naturalAngularFrequency`,
  `fundamentalAntisymmetricRectangular`, `naturalPeriodSec`.
- `rectangular.deepWaterLimitOmega`, `shallowWaterLimitOmega`.
- 12-test unit suite including closed-form k_n, Faltinsen-Timokha
  4.3.1 worked example, deep / shallow limits, and monotone
  mode-frequency ordering.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
