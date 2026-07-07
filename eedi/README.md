# yard-eedi-zig

Proof level: `unit-tested`

yard-eedi-zig is a Zig 0.16 IMO Energy Efficiency Design Index
(EEDI) attained-value kernel per MEPC.308(73) in the simplified
main-engine + auxiliary-engine form, with carbon-conversion factors
from MEPC.337(76) and Phase 0/1/2/3 reduction factors from
MEPC.328(76) (bulk carrier DWT >= 20 000 t table).

## What it does

- `eedi.FuelType` enum with `carbonFactorKgCO2PerKgFuel()` returning
  C_F per MEPC.337(76) for HFO, LFO, MDO, MGO, LPG (propane and
  butane), LNG, methanol, and ethanol.
- `eedi.Engine` typed struct (P_kw, SFC_g_per_kwh, fuel).
- `eedi.EEDIInputs` packs main engines, auxiliary engines, capacity,
  V_ref, and capacity correction factor f_i.
- `eedi.attainedValueGCO2PerTNm(in)` evaluates the simplified EEDI
  numerator-denominator quotient and returns g CO2 per t * nm.
- `eedi.Phase` enum and `bulkCarrierReductionFactor` for the four
  EEDI phases.
- `eedi.requiredValueGCO2PerTNm(baseline, phase)` applies the
  reduction factor.
- `eedi.verdict(attained, required)` returns pass / fail.

## What it is not (v0.0.0)

- No ship-type baseline-reference-line catalogue (caller supplies
  the baseline value derived from a / b / c regression).
- No innovative-technology / shaft-generator / waste-heat-recovery
  bonus calculation (terms P_AE_eff, P_eff, C_F_eff in the full
  formula).
- No reference-speed sea-trial-correction wave / wind / current
  loops.
- No correction-factor catalogue (ice class, cubic capacity, ro-ro).
- No CII / SEEMP companion (would compose externally).
- No multi-fuel dual-fuel C_F blending (single fuel per engine entry).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 12/12 tests passed`.

## Public API

```zig
const yard = @import("yard_eedi");

const me = [_]yard.eedi.Engine{
    .{ .P_kw = 10_000.0, .SFC_g_per_kwh = 190.0, .fuel = .HFO },
};
const ae = [_]yard.eedi.Engine{
    .{ .P_kw = 600.0, .SFC_g_per_kwh = 215.0, .fuel = .MGO },
};
const in: yard.eedi.EEDIInputs = .{
    .main_engines = &me,
    .auxiliary_engines = &ae,
    .capacity_t = 50_000.0,
    .V_ref_kt = 15.0,
    .f_i = 1.0,
};
const attained = try yard.eedi.attainedValueGCO2PerTNm(in);

const required = try yard.eedi.requiredValueGCO2PerTNm(10.0, .phase_2);
const v = yard.eedi.verdict(attained, required);
```

## Validation

- Carbon factors match MEPC.337(76) listed values: HFO 3.114, MGO
  3.206, LNG 2.750.
- Numerator-denominator quotient matches the hand-computed
  10-MW ME + 0.6-MW AE worked example.
- Zero-engine inputs yield zero attained.
- Switching ME fuel from HFO to LNG at the same SFC scales the
  attained value by 2.750 / 3.114.
- Reduction-factor table is monotone increasing through Phase 0..3.
- Required EEDI Phase 2 (X = 20 %) is 80 % of baseline.
- Verdict pass at attained <= required, fail otherwise.
- Typed-error rejection for non-positive capacity, V_ref, power,
  SFC, and f_i below 1.0.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- IMO Resolution MEPC.308(73). 2018 Guidelines on the method of
  calculation of the attained EEDI.
- IMO Resolution MEPC.328(76). Amendments to MARPOL Annex VI
  (EEDI Phase 3 / Phase 4 transition).
- IMO Resolution MEPC.337(76). 2021 Guidelines on the use of
  alternative fuel oils.
- Bouman, E. A., Lindstad, E., Rialland, A. I., Stromman, A. H.
  (2017). *State-of-the-art technologies, measures, and potential for
  reducing GHG emissions from shipping*. Transportation Research D.

## License

Apache-2.0.
