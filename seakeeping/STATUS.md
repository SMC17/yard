# Status

yard-seakeeping-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `spectra.piersonMoskowitz` | `unit-tested` | Zero at omega=0; positive at typical omega |
| `spectra.jonswap` | `unit-tested` | gamma=1 collapses to Pierson-Moskowitz within f64 round-off; gamma > 1 exceeds PM at peak |
| `spectra.ittcModifiedPM` | `unit-tested` | Zero at omega=0; H_s^2 scaling check; T_z-dependent shape check |
| `moments.momentITTC` | `unit-tested` | m_0 recovers (H_s/4)^2 within 0.1 percent at 8001 samples; even-sample rejection; inverted-range rejection; streaming Simpson 1/3 (no allocation) |
| `moments.hsFromM0` | `unit-tested` | Roundtrip H_s -> m_0 -> H_s within 1 percent; non-positive rejection |
| `moments.tzFromMoments` | `unit-tested` | Roundtrip T_z -> (m_0, m_2) -> T_z within 5 percent at 8001 samples; non-positive rejection |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `16/16 tests pass`.

```
zig build test --summary all
```

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: tolerance bands match the published
  spectral-moment convergence behavior. H_s recovers within 1 percent;
  T_z within 5 percent. Both are caller-tunable via sample count.
- Type-II missed risk guard: explicit error variants for even sample
  count, non-positive spacing, non-positive moment.
- Type-III category guard: spectral PSD only. Not a ship-motion
  evaluator (RAO computation is downstream), not a wave-scatter
  convolver.

## What is not covered (v0.0.0)

- Bretschneider, ISSC, Ochi-Hubble, multi-peak, double-peaked spectra.
- Directional spectra D(theta).
- Strip-theory RAO computation.
- Wave-scatter-diagram convolution for long-term statistics.
- Encounter-frequency transformation (for forward-speed effects).

## Validation against codex substrate

Formulas trace to
`~/codex/concepts/wave-spectra-jonswap-pierson-moskowitz.md` and
`~/codex/concepts/salvesen-tuck-faltinsen-strip-theory.md`.
