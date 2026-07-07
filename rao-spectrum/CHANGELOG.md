# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `spectrum.simpsonUniform` Simpson 1/3 with 3/8 tail closure.
- `spectrum.spectralMoment` n-th spectral moment.
- `spectrum.responseSpectrum` element-wise `|H|^2 S` product.
- `spectrum.significantResponseAmplitude` 4 sqrt(m_0).
- `spectrum.meanZeroCrossingPeriod` 2 pi sqrt(m_0/m_2).
- 14-test unit suite including quadrature exactness on x^2 and x^3,
  closed-form moment, RAO amplification, and rejected inputs.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
