# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `spectra.piersonMoskowitz(omega, alpha, omega_0)` PSD.
- `spectra.jonswap(omega, alpha, omega_p, gamma)` PSD with the
  peak-enhancement gamma; reduces to Pierson-Moskowitz at gamma=1.
- `spectra.ittcModifiedPM(omega, H_s, T_z)` ITTC convenience
  parametrization.
- `moments.momentITTC` streaming Simpson 1/3 integration of
  `omega^n S(omega)` over a truncated range with no heap allocation.
- `moments.hsFromM0` and `moments.tzFromMoments` derived-statistics
  helpers.
- 16-test unit suite including roundtrip cross-check between input
  (H_s, T_z) and integrated-and-back-computed values.
- Bench step measuring ittcModifiedPM and momentITTC latency.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
