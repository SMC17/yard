# Status

yard-eedi-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `eedi.FuelType.carbonFactorKgCO2PerKgFuel` | `claimed` | values transcribed from MEPC.337(76); no independent reproducer beyond reading the resolution |
| `eedi.attainedValueGCO2PerTNm` | `unit-tested` | 10-MW + 0.6-MW worked example reproduces hand-computed numerator-denominator quotient; LNG vs HFO swap scales by exactly 2.750 / 3.114; zero-engine zero attained |
| `eedi.bulkCarrierReductionFactor` | `claimed` | values transcribed from MEPC.328(76) bulk-carrier Phase 0..3 column; monotone-increasing test ordering verified |
| `eedi.requiredValueGCO2PerTNm` | `unit-tested` | Phase 2 -> 80 % of baseline |
| `eedi.verdict` | `unit-tested` | <= boundary inclusion |

## Coverage caveat

The carbon-factor and reduction-factor tables are transcribed from
the relevant IMO Resolutions. For regulatory submission the caller
must verify against the official text and the ship-type baseline
reference line.

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `12/12 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: C_F and X tables flagged `claimed` until
  re-verified against the official MEPC text; the formula logic is
  `unit-tested`.
- Type-II missed risk guard: typed-error rejection for non-positive
  capacity, V_ref, power, SFC, and f_i below 1.0. f_i = 1.0 is the
  no-correction default; values below 1.0 are nonsensical per the
  resolution.
- Type-III category guard: attained-value calculator only; not a
  baseline reference line evaluator; not an innovative-technology
  bonus calculator; not a CII / SEEMP companion; not a sea-trial
  V_ref correction engine.

## What is not covered (v0.0.0)

- Baseline reference line per ship type (caller supplies).
- Innovative-technology / shaft-generator / waste-heat-recovery
  bonuses.
- Sea-trial wave / wind / current corrections for V_ref.
- Capacity correction catalogue (ice class, cubic, ro-ro).
- CII / SEEMP companion.
- Multi-fuel dual-fuel C_F blending.

## Composition

- `Engine.P_kw` at 75 % MCR couples to `yard-ittc78-zig::Result.SHP_kw`
  via `P_ME = 0.75 * SHP / eta_TRM`.
- `V_ref_kt` couples to the same powering chain at the design draft.
- `capacity_t` couples to deadweight derived from `yard-stability-zig`
  + `yard-hydro-zig` displacement minus lightship weight.
