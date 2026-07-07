# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `freeboard.ShipType` enum.
- `freeboard.tabularFreeboardMm` linear interpolation on eight-point
  ICLL Annex I grid.
- `freeboard.blockCoefficientCorrection` per Reg. 30.
- `freeboard.depthCorrectionMm` per Reg. 31.
- `freeboard.superstructureDeductionMm` per Reg. 37.
- `freeboard.summerFreeboardMm` composer.
- 15-test unit suite including tabular endpoints, Type A vs Type B
  ordering, midpoint interpolation, C_B factor, depth correction in
  both R-branches, and full composition.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

Tabular freeboard grid is an eight-point sub-sample of the one-metre
ICLL table; proof level `claimed` for the table, `unit-tested` for
correction logic.
