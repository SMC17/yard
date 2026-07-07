# yard-cii-zig

Proof level: `unit-tested`

yard-cii-zig is a Zig 0.16 IMO Carbon Intensity Indicator (CII)
operational-rating kernel per MEPC.354(78). Attained Annual Efficiency
Ratio (AER), year-specific Z reduction factor lookup 2019..2030,
required CII = baseline * (1 - Z), and the bulk-carrier A..E rating
classification per the d1..d4 vectors in Annex 2.

## What it does

- `cii.FuelType` enum with `carbonFactor()` per MEPC.337(76) (subset
  shared with `yard-eedi-zig`).
- `cii.FuelEntry` typed struct (fuel, consumption_t).
- `cii.attainedAERgCO2PerTNm(fuels, capacity_t, distance_nm)` returns
  the per-tonne-mile attained AER.
- `cii.reductionFactorZ(year)` returns the year-specific Z fraction
  for 2019 (baseline), 2023..2030 per MEPC.354(78).
- `cii.requiredCIIgCO2PerTNm(baseline, year)` returns
  `baseline * (1 - Z)`.
- `cii.Rating` A..E enum and `classifyBulkCarrier(attained, required)`
  applies the bulk-carrier dd vectors `d1 = 0.86, d2 = 0.94,
  d3 = 1.06, d4 = 1.18`.

## What it is not (v0.0.0)

- No ship-type baseline-reference-line catalogue (caller supplies).
- No corrections for ice class, voyage type, weather (compose
  externally with the MEPC.354(78) correction toolkit).
- No multi-year trend tracking (caller maintains the time series).
- No DCS / IMO data-collection-system report-generation.
- No SEEMP / Ship Energy Efficiency Management Plan companion.
- No SEEMP Part III enhancement compliance check.
- No tanker / container-ship / cruise-ship rating vectors (bulk only).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 12/12 tests passed`.

## Public API

```zig
const yard = @import("yard_cii");

const fuels = [_]yard.cii.FuelEntry{
    .{ .fuel = .HFO, .consumption_t = 1000.0 },
    .{ .fuel = .LNG, .consumption_t = 500.0 },
};
const attained = try yard.cii.attainedAERgCO2PerTNm(&fuels, 50_000.0, 60_000.0);
const required = try yard.cii.requiredCIIgCO2PerTNm(5.0, 2026);
const rating = yard.cii.classifyBulkCarrier(attained, required);
```

## Validation

- Carbon factors match MEPC.337(76) HFO 3.114 and LNG 2.750.
- Single-fuel HFO voyage: 1000 t HFO * 3.114 * 1e6 / (50000 * 60000)
  matches closed form; resulting AER ~ 1.038 g / t / nm.
- Attained AER scales linearly with fuel consumption.
- Switching HFO -> LNG scales AER by 2.750 / 3.114.
- Z reduction factor 2023 -> 0.05, 2024 -> 0.07, 2030 -> 0.19.
- Z factor is monotone-increasing across 2023..2030.
- Required CII at baseline 5.0 and 2030 (Z = 0.19) equals 4.05.
- Bulk-carrier rating thresholds match exactly:
  - 0.80 < 0.86 -> A
  - 0.90 in [0.86, 0.94) -> B
  - 1.00 in [0.94, 1.06) -> C
  - 1.10 in [1.06, 1.18) -> D
  - 1.20 >= 1.18 -> E
- Typed-error rejection for zero capacity, zero distance,
  unknown year.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- IMO Resolution MEPC.354(78). *Guidelines on the Operational
  Carbon Intensity Indicators and the Calculation Methods*.
- IMO Resolution MEPC.353(78). *Guidelines on the Reference Lines
  for use with the operational CII*.
- IMO Resolution MEPC.339(76). *Guidelines on the Operational
  Carbon Intensity Rating of Ships*.
- IMO Resolution MEPC.337(76). *2021 Guidelines on the use of
  alternative fuel oils*.

## License

Apache-2.0.
