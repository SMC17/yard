# Status

yard-cii-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `cii.FuelType.carbonFactor` | `claimed` | MEPC.337(76) values transcribed; subset of EEDI catalogue |
| `cii.attainedAERgCO2PerTNm` | `unit-tested` | single-fuel HFO closed-form match; linear FC scaling; LNG/HFO ratio = 2.750 / 3.114 |
| `cii.reductionFactorZ` | `claimed` | year-by-year Z values transcribed from MEPC.354(78); monotone-increasing verification in tests |
| `cii.requiredCIIgCO2PerTNm` | `unit-tested` | baseline * (1 - Z) closed form |
| `cii.classifyBulkCarrier` | `unit-tested` | five-band boundary verification at 0.86, 0.94, 1.06, 1.18 |

## Coverage caveat

The Z-reduction values and carbon factors are transcribed from
MEPC.354(78) and MEPC.337(76). For regulatory submission caller
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

- Type-I overclaim guard: Z table and rating vectors flagged
  `claimed` until cross-verified against the official text. The
  AER formula and dd-band classification logic are `unit-tested`.
- Type-II missed risk guard: typed-error rejection for zero capacity,
  zero distance, non-positive fuel, unknown year.
- Type-III category guard: AER-style operational rating only; not
  a SEEMP companion; not a DCS report generator; not a corrections
  toolkit for ice class / voyage type / weather; not a tanker /
  container / cruise ship classifier.

## What is not covered (v0.0.0)

- Ship-type baseline reference line catalogue (caller supplies).
- Voyage / ice class / weather correction factors.
- DCS / IMO data-collection-system report.
- SEEMP / SEEMP Part III companion.
- Multi-year trend tracking.
- Tanker / container / cruise / passenger ship rating vectors.

## Composition

- Per-fuel `consumption_t` inputs couple to `yard-engine-zig`
  `fuelMassFlowKgPerHr` integrated over the year times operating
  hours.
- `capacity_t` aligns with `yard-eedi-zig::EEDIInputs.capacity_t`
  reference deadweight definition.
- `distance_nm` couples to `yard-routing-zig` great-circle voyage
  distance accumulated over the year.
