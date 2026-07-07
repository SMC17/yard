# yard-seakeeping-zig

Proof level: `unit-tested`

yard-seakeeping-zig is a Zig 0.16 implementation of three wave power-
spectral-density functions (Pierson-Moskowitz, JONSWAP, ITTC modified
PM), plus spectral-moment integration and derived (H_s, T_z) statistics.

## What it does

- `spectra.piersonMoskowitz(omega, alpha, omega_0)` fully-developed
  wind-sea PSD.
- `spectra.jonswap(omega, alpha, omega_p, gamma)` JONSWAP fetch-limited
  PSD; collapses to Pierson-Moskowitz when gamma = 1.
- `spectra.ittcModifiedPM(omega, H_s, T_z)` ITTC convenience
  parametrization in significant wave height and zero-up-crossing
  period.
- `moments.momentITTC(n, H_s, T_z, omega_lo, omega_hi, samples)`
  streaming Simpson 1/3 of `omega^n S(omega) domega`; no heap
  allocation.
- `moments.hsFromM0(m_0)` = `4 sqrt(m_0)`.
- `moments.tzFromMoments(m_0, m_2)` = `2 pi sqrt(m_0 / m_2)`.

## What it is not (v0.0.0)

- No Bretschneider, ISSC, Ochi-Hubble, or other spectrum families.
- No directional spectra (no D(theta) spreading).
- No strip-theory RAO computation.
- No wave-scatter-diagram convolution.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 16/16 tests passed`.

## Bench

```
zig build bench -Doptimize=ReleaseFast
```

## Public API

```zig
const yard = @import("yard_seakeeping");

const s_pm = yard.spectra.piersonMoskowitz(0.7, 0.0081, 0.6);
const s_js = yard.spectra.jonswap(0.7, 0.0081, 0.6, 3.3);
const s_ittc = yard.spectra.ittcModifiedPM(0.7, 4.0, 8.0);

// Spectral moments and derived statistics.
const m0 = try yard.moments.momentITTC(0, 4.0, 8.0, 0.001, 4.0, 8001);
const m2 = try yard.moments.momentITTC(2, 4.0, 8.0, 0.001, 4.0, 8001);
const H_s = try yard.moments.hsFromM0(m0);
const T_z = try yard.moments.tzFromMoments(m0, m2);
```

## Validation

ITTC modified PM has the convenient analytical property that

```
m_0 = (H_s / 4)^2 = 1.0 m^2  for H_s = 4 m
```

The roundtrip test verifies that integrating the spectrum and back-
computing H_s recovers the input within 1 percent at 8001-sample
Simpson integration over omega in [0.001, 4.0].

T_z recovers within 5 percent at the same sample density (T_z requires
m_2, which weights higher frequencies and converges more slowly under
high-frequency truncation).

JONSWAP with gamma = 1 reduces exactly to Pierson-Moskowitz, verified
to f64 round-off.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0). Strongest
available claim: `stable-on-zig-0.16-today`.

## References

- Pierson, W. J. and Moskowitz, L. (1964), "A proposed spectral form
  for fully developed wind seas," Journal of Geophysical Research
  69:24, pp 5181-5190.
- Hasselmann, K. et al. (1973), "Measurements of wind-wave growth and
  swell decay during the Joint North Sea Wave Project (JONSWAP),"
  Deutsche Hydrographische Zeitschrift A8:12, pp 1-95.
- ITTC Recommended Procedure 7.5-02-07-02.1 (Seakeeping Experiments).
- Faltinsen, O. M. (1990), *Sea Loads on Ships and Offshore
  Structures*, Cambridge UP, Ch. 2-3.
- Codex cross-references at
  `~/codex/concepts/wave-spectra-jonswap-pierson-moskowitz.md`.

## License

AGPL-3.0-or-later. See `LICENSE`.
