# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `ur_s11.waveCoefficient` piecewise C(L) for 90 to 500 m.
- `ur_s11.waveMomentHog` and `ur_s11.waveMomentSag` (kN*m).
- `ur_s11.SteelGrade` enum (mild, ht32, ht36, ht40) with `k` and
  `yieldMpa` methods per UR S4.
- `ur_s11.permissibleStressMpa(grade)` = 175 / k.
- `ur_s11.minSectionModulus(M, grade)` and
  `ur_s11.minMomentOfInertia(Z, L)`.
- 16-test unit suite including cross-check against Hughes/Paik 2010
  Ch.4 bulker worked example.
- Bench step measuring waveCoefficient and waveMomentHog latency.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
