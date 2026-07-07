# yard-rao-spectrum-zig

Proof level: `unit-tested`

yard-rao-spectrum-zig is a Zig 0.16 wave-spectrum and RAO-convolution
kernel. Given a wave spectrum `S(omega)` and a response-amplitude
operator squared `|H(omega)|^2`, the kernel forms the response spectrum
`S_R(omega) = |H(omega)|^2 S(omega)`, integrates its `n`-th moment via
Simpson 1/3 (with 3/8 closure on odd-interval-count tails), and
returns the significant response amplitude per the Rayleigh narrow-band
formula `H_s_R = 4 sqrt(m_0)`.

## What it does

- `spectrum.simpsonUniform(f, h)` Simpson 1/3 over a uniformly spaced
  ordinate array, with automatic 3/8 closure when the number of
  intervals is odd. Allocator-free.
- `spectrum.spectralMoment(n, omega, S)` the `n`-th spectral moment of
  an arbitrary `S(omega)` on uniformly spaced ordinates. Validates
  equal length, sorted ascending, uniform spacing, and at least four
  points.
- `spectrum.responseSpectrum(H_sq, S, out)` element-wise multiplication
  into a caller-supplied output buffer.
- `spectrum.significantResponseAmplitude(m0)` `4 sqrt(m0)` Rayleigh
  narrow-band amplitude.
- `spectrum.meanZeroCrossingPeriod(m0, m2)` `T_z = 2 pi sqrt(m0/m2)`.

## What it is not (v0.0.0)

- No FFT-based convolution (this is a quadrature kernel; for irregular
  ordinates an interpolator must be applied first by the caller).
- No automatic wave-spectrum generator (compose with
  `yard-seakeeping-zig` for PM, JONSWAP, ITTC-modified-PM).
- No directional spreading (long-crested only).
- No nonlinear response statistics (caller assumes narrow-band
  Rayleigh).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 14/14 tests passed`.

## Public API

```zig
const yard = @import("yard_rao_spectrum");

var omega: [N]f64 = ...; // uniform ascending
var S: [N]f64 = ...;     // wave spectrum at omega
var H_sq: [N]f64 = ...;  // |RAO|^2 at omega
var SR: [N]f64 = undefined;
try yard.spectrum.responseSpectrum(&H_sq, &S, &SR);
const m0 = try yard.spectrum.spectralMoment(0, &omega, &SR);
const m2 = try yard.spectrum.spectralMoment(2, &omega, &SR);
const Hs_R = yard.spectrum.significantResponseAmplitude(m0);
const Tz_R = yard.spectrum.meanZeroCrossingPeriod(m0, m2);
```

## Validation

- Simpson 1/3 on `x^2` over [0, 1] yields 1/3 to 1e-12.
- Simpson 1/3 + 3/8 tail on `x^3` over [0, 1] yields 1/4 to 1e-12 with
  N=12 (odd interval count).
- m_0 of `S = 2` over [1, 3] equals 4 to 1e-12.
- m_1 of `S = 1` over [1, 3] equals 4 to 1e-12.
- `|H|^2 = 1` reproduces wave m_0 in the response spectrum.
- Constant `|H|^2 = 4` over `S = 1` band gives response m_0 = 8 and
  H_s_R = 4 sqrt(8).
- `T_z = 2 pi sqrt(m_0 / m_2)` exact closed-form match.
- Unequal-length, non-uniform-spacing, and unsorted-omega inputs are
  rejected with typed errors.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Faltinsen, O. (1990). *Sea Loads on Ships and Offshore Structures*.
  Cambridge.
- Ochi, M. K. (1998). *Ocean Waves: The Stochastic Approach*.
  Cambridge.
- ITTC Recommended Procedure 7.5-02-07-02.1 (2017). Seakeeping
  experiments.

## License

Apache-2.0.
