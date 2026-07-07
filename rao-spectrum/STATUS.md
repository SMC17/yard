# Status

yard-rao-spectrum-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `spectrum.simpsonUniform` | `unit-tested` | x^2 over [0,1] = 1/3 with N=11; x^3 over [0,1] = 1/4 with N=12 exercises 3/8 closure |
| `spectrum.spectralMoment` | `unit-tested` | m_0 of S=2 over [1,3] = 4; m_1 of S=1 over [1,3] = 4 |
| `spectrum.responseSpectrum` | `unit-tested` | element-wise product validated against hand-multiplied 5-element vectors |
| `spectrum.significantResponseAmplitude` | `unit-tested` | 4 sqrt(m_0) closed form |
| `spectrum.meanZeroCrossingPeriod` | `unit-tested` | 2 pi sqrt(m_0/m_2) closed form |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `14/14 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: `spectralMoment` rejects unequal-length
  inputs, non-uniform omega spacing, and unsorted omega ordinates with
  typed errors. The kernel does not silently corrupt the integral.
- Type-II missed risk guard: 3/8 closure on odd-interval tails so the
  trapezoid-vs-Simpson order is not silently degraded on even N.
- Type-III category guard: scalar quadrature kernel only; not an FFT;
  not a wave-spectrum generator (use `yard-seakeeping-zig`); not a
  motion solver (use `yard-coupled-motions-zig`).

## What is not covered (v0.0.0)

- FFT-based convolution.
- Directional / short-crested spreading.
- Non-uniform omega ordinates (interpolate externally).
- Nonlinear / non-Gaussian response statistics.
- Buffer size beyond 4096 ordinates (caller must integrate in
  segments).

## Composition

- Inputs `|H(omega)|^2` from `yard-strip-theory-zig` or
  `yard-coupled-motions-zig::raoMagnitudes` squared elementwise.
- Inputs `S(omega)` from `yard-seakeeping-zig`'s PM, JONSWAP, or
  ITTC-modified-PM kernels.
- Output `m_0`, `m_2` plus `T_z`, `H_s_R` feed offshore-loading or
  fatigue spectra in `yard-csr-fatigue-zig`.
