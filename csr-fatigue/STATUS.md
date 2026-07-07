# Status

yard-csr-fatigue-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `sn.DetailClass.params` | `claimed` | numeric values copied from DNV-RP-C203 Table 2-1 (air); no independent reproducer; should be re-verified against the PDF before any compliance use |
| `sn.kneeStressMPa` | `unit-tested` | D class -> 52.63 MPa to 0.05 |
| `sn.cyclesToFailure` | `unit-tested` | D at 160 MPa matches log N = 12.164 - 3 log(160); D at 30 MPa matches log N = 15.606 - 5 log(30); knee maps to N = 1e7; class ordering C > D > W3; thickness reduction scaling |
| `miner.cumulativeDamage` | `unit-tested` | single-block 0.1; two-block 0.5; sum > 1.0 marks failure |
| `miner.verdict` | `unit-tested` | D = 1.0 returns `.fail` (>=1 threshold) |
| `miner.remainingLifeFromCurrentBlock` | `unit-tested` | D = 0 -> infinity; D = 0.5, n=1e6 -> 1e6; D >= 1 -> 0 |

## Caveat (Type-I overclaim guard)

The numeric S-N parameter table is a transcription, not a verified
external-reference reproduction. Real fatigue-assessment work must
cross-check against the DNV PDF. The proof level for the table itself
is `claimed`; the evaluation logic is `unit-tested`.

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `20/20 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: detail-class parameter table flagged
  `claimed` until externally re-verified against DNV-RP-C203 PDF;
  evaluation logic separate `unit-tested`.
- Type-II missed risk guard: thickness reduction kicks in
  automatically for t > t_ref so callers cannot silently underestimate
  damage on thick plates; bilinear slope branch selected per stress
  vs knee.
- Type-III category guard: linear-cumulative-damage kernel only; not
  a rainflow decomposer; not a hot-spot K_s library; not a
  multi-axial principal-stress reorientation engine.

## What is not covered (v0.0.0)

- Seawater (cathodic / free-corrosion) curves.
- Hot-spot stress concentration factors.
- Rainflow stress-block extraction from time history.
- Multi-axial -> uniaxial range reduction.
- Mean-stress (Goodman / Soderberg) correction.
- Probabilistic life distribution.

## Composition

- `yard-rao-spectrum-zig` provides spectral m_0, m_2 for stress range
  variance and zero-crossing rate; a spectral-fatigue post-processor
  is the natural next downstream kernel.
- Caller composes externally with the buckling check
  (`yard-csr-buckling-zig`) for combined ultimate + fatigue verdicts.
