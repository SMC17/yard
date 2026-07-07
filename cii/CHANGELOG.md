# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `cii.FuelType` enum and `carbonFactor()`.
- `cii.FuelEntry` typed struct.
- `cii.attainedAERgCO2PerTNm` per-tonne-mile AER.
- `cii.reductionFactorZ` 2019..2030 Z lookup.
- `cii.requiredCIIgCO2PerTNm` baseline * (1 - Z).
- `cii.Rating` enum and `classifyBulkCarrier` A..E classifier.
- 12-test unit suite covering carbon-factor propagation, single-
  fuel AER closed form, linear FC scaling, HFO -> LNG fuel-switch
  ratio, year-Z monotonicity, 2030 worked example, bulk-carrier
  five-band threshold check, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

Z reduction-factor and rating-band tables transcribed from
MEPC.354(78); flagged `claimed` until externally re-verified.
