# Status

yard-load-line-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `freeboard.tabularFreeboardMm` | `claimed` | eight-point grid transcribed from ICLL Annex I Reg. 28; one-metre tabular granularity not yet ingested |
| `freeboard.blockCoefficientCorrection` | `unit-tested` | (C_B + 0.68)/1.36 closed form; unity at C_B <= 0.68 |
| `freeboard.depthCorrectionMm` | `unit-tested` | zero at D = L/15; R = L/0.48 above 120 m and 250 below |
| `freeboard.superstructureDeductionMm` | `unit-tested` | zero at E/L = 0; 1070 mm ceiling at E/L = 1 for L >= 122 m |
| `freeboard.summerFreeboardMm` | `unit-tested` | reproduces composed F_tab * k_CB + dF_depth - dF_super |

## Coverage caveat

The tabular freeboard grid is an eight-point sub-sample of the
full one-metre ICLL Annex I table. Linear interpolation between
grid points introduces sub-millimetre rounding error at most lengths
but can deviate by a few millimetres near sharp kinks in the
published curve. For one-millimetre-precision assignment work the
caller must load the official ICLL table externally; the kernel
flags this branch as `claimed`.

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `15/15 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: tabular grid flagged `claimed` because of
  the linear-interpolation approximation; corrections themselves are
  `unit-tested` against the published Reg. 30, 31, 37 formulas.
- Type-II missed risk guard: typed-error rejection for non-positive
  length / depth, out-of-range C_B, out-of-range E/L, and length
  outside the tabular [24, 365] m range.
- Type-III category guard: assigns freeboard only; not a
  watertight-integrity verification engine; not a sheer-correction
  calculator (Reg. 38); not a bow-height checker (Reg. 39); not a
  timber load-line evaluator.

## What is not covered (v0.0.0)

- Tropical / winter / winter-North-Atlantic zone marks.
- Sheer correction (Reg. 38).
- Bow-height check (Reg. 39).
- Timber load-line marks.
- One-metre table granularity beyond the eight-point grid.

## Composition

- Composes with `yard-stability-zig` for the integrated stability +
  freeboard check.
- Composes with `yard-hydro-zig` block-coefficient output for the
  C_B input.
