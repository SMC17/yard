# Status

yard-noise-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `urn.sphericalSpreadingDb` | `unit-tested` | 6 dB / doubling; 20 dB / decade; 0 dB at r = r_ref |
| `urn.cylindricalSpreadingDb` | `unit-tested` | 3 dB / doubling |
| `urn.thorpAbsorptionDbPerM` | `unit-tested` | closed-form match at 10 kHz; monotone increase to 100 kHz |
| `urn.transmissionLossDb` | `unit-tested` | r=100, alpha=0.01 gives 40.99 dB closed form |
| `urn.sourceLevelDbReference1m` | `unit-tested` | SPL=100 dB at r=100 m gives SL=140 dB; absorption adds alpha*(r-1) |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `13/13 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: Thorp 1967 fit is the simple form valid
  in deep sea-water; near-coast / fresh-water absorption may differ
  by tens of percent. The kernel does not silently extrapolate
  outside the standard regime.
- Type-II missed risk guard: typed-error rejection for zero / negative
  range, negative absorption, zero frequency.
- Type-III category guard: spreading + absorption only; not a
  Lloyd-mirror calculator; not a bathymetric ray tracer; not a
  directivity / array-gain engine; not an ambient-noise model.

## What is not covered (v0.0.0)

- Lloyd-mirror surface-interference effects.
- Bathymetric ray tracing.
- Bottom-loss correction.
- Source directivity / array gain.
- Ambient noise subtraction.
- Frequency-band SPL spectrum integration.

## Composition

- Output source level couples to ship-design vibration / cavitation
  inception predictions via `yard-cavitation-zig`; high source levels
  in the 10..1000 Hz band typically correlate with propeller
  cavitation regimes flagged by Burrill.
