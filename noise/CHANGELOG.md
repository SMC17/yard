# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `urn.sphericalSpreadingDb` 20 log10(r/r_ref).
- `urn.cylindricalSpreadingDb` 10 log10(r/r_ref).
- `urn.thorpAbsorptionDbPerM` Thorp 1967 approximation.
- `urn.transmissionLossDb` combined spreading + absorption.
- `urn.sourceLevelDbReference1m` SPL_measured + TL to 1 m.
- 13-test unit suite including 6 dB / doubling, 20 dB / decade,
  cylindrical 3 dB / doubling, Thorp closed form, and
  140 dB source-level worked example.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
