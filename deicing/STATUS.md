# Status

yard-deicing-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `overland.predictorIndex` | `unit-tested` | closed form at V=15, T_air=-10, T_sea=5 = 33.83; linear wind scaling |
| `overland.classifyByIndex` | `unit-tested` | boundary mapping 0 / 22.4 / 53.3 / 83 verified |
| `overland.classifyByConditions` | `unit-tested` | composer reproduces moderate class at the worked-example conditions |
| `accreted.accretedMassKg` | `unit-tested` | 900 kg at 10 mm / 100 m^2; linear scaling |
| `accreted.accretionRateMperHrForClass` | `claimed` | 0 / 0.003 / 0.010 / 0.020 / 0.040 m/hr first-order Coast Guard / NOAA values; per-vessel calibration deferred |
| `accreted.totalAccretedWeightKg` | `unit-tested` | 10 800 kg at 10 mm/hr / 12 hr / 100 m^2 |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `22/22 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: Overland 1986 predictor is a sea-spray
  icing classifier; the kernel does not claim to compute mixed-phase
  atmospheric icing. Class rates flagged `claimed`.
- Type-II missed risk guard: typed-error rejection for negative
  wind speed, extreme temperature, zero thickness / duration / area.
- Type-III category guard: indicator + weight-accumulation kernel
  only; not a de-icing-system sizing engine; not a stability-impact
  predictor (compose with `yard-stability-zig`); not a directional
  spray-zone map.

## What is not covered (v0.0.0)

- Mixed-phase atmospheric + sea-spray icing.
- De-icing-system sizing.
- Directional spray-zone map.
- IMO Polar Code icing-allowance lookup.
- Anti-icing chemistry.
- KG impact (compose externally).

## Composition

- Inputs V_wind, T_air, T_sea from a meteorological dataset.
- Output accreted weight composes with `yard-stability-zig` KG-
  raising calculation: heavy icing on a high topside raises KG and
  can violate IS Code criteria.
- Polar Code arrangement studies couple this with
  `yard-icebreaker-zig` ice-resistance.
