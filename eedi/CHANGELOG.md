# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `eedi.FuelType` enum and `carbonFactorKgCO2PerKgFuel` per
  MEPC.337(76).
- `eedi.Engine`, `eedi.EEDIInputs` typed structs.
- `eedi.attainedValueGCO2PerTNm` simplified attained-value formula.
- `eedi.Phase` enum and `bulkCarrierReductionFactor` per MEPC.328(76).
- `eedi.requiredValueGCO2PerTNm` baseline * (1 - X).
- `eedi.verdict` pass / fail.
- 12-test unit suite including C_F table check, worked example,
  LNG vs HFO ratio, phase ordering, required calculation, and
  typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

Carbon-factor and Phase reduction-factor tables transcribed from
IMO Resolutions; flagged `claimed` until externally re-verified.
