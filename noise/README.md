# yard-noise-zig

Proof level: `unit-tested`

yard-noise-zig is a Zig 0.16 underwater radiated-noise kernel per
ITTC Recommended Procedure 7.5-04-04-01. Spherical and cylindrical
transmission loss, Thorp 1967 absorption-coefficient fit, and the
SPL_source = SPL_measured + TL reduction to the 1 m reference range.

## What it does

- `urn.sphericalSpreadingDb(r, r_ref)` returns
  `20 log10(r / r_ref)`.
- `urn.cylindricalSpreadingDb(r, r_ref)` returns
  `10 log10(r / r_ref)`.
- `urn.thorpAbsorptionDbPerM(freq_khz)` returns the Thorp 1967
  approximation `1.1e-4 f^2 + 0.011 / (1 + f^2)` in dB/m.
- `urn.transmissionLossDb(r, r_ref, alpha)` total TL combining
  spherical spreading and linear absorption.
- `urn.sourceLevelDbReference1m(SPL_measured, r, alpha)` returns the
  1 m reference source level `SPL_measured + TL` in dB re 1 µPa @
  1 m.

## What it is not (v0.0.0)

- No frequency-band SPL spectrum integration (caller supplies a
  single SPL number; band-by-band reduction is one outer loop away).
- No Lloyd-mirror / sea-surface interference effects.
- No bathymetric ray tracing (compose with a sound-speed-profile
  model for deep-ocean propagation).
- No bottom-loss correction.
- No directivity correction (assumes omnidirectional source).
- No ambient-noise subtraction.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 13/13 tests passed`.

## Public API

```zig
const yard = @import("yard_noise");

const alpha = try yard.urn.thorpAbsorptionDbPerM(10.0); // 10 kHz
const SL = try yard.urn.sourceLevelDbReference1m(140.0, 100.0, alpha);
```

## Validation

- Spherical spreading at `r = r_ref` returns 0 dB.
- Spherical spreading 6 dB per doubling of range.
- Spherical spreading 20 dB per decade of range.
- Cylindrical spreading 3 dB per doubling of range.
- Thorp absorption at 10 kHz matches
  `1.1e-4 * 100 + 0.011 / 101` to 1e-12.
- Thorp absorption at 100 kHz exceeds value at 10 kHz.
- Total TL at r = 100 m, alpha = 0.01 dB/m equals 40.990 dB
  (40 dB spherical + 0.99 dB absorption).
- Source level: SPL = 100 dB at r = 100 m and alpha = 0 reduces to
  SL = 140 dB re 1 µPa @ 1 m.
- Absorption contributes alpha * (r - 1) dB to the source level.
- Typed-error rejection for zero range, negative absorption, zero
  frequency.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- ITTC Recommended Procedure 7.5-04-04-01. *Underwater Noise from
  Ships, Full Scale Measurements*.
- Thorp, W. H. (1967). *Analytic Description of the Low-Frequency
  Attenuation Coefficient*. JASA 42.
- Urick, R. J. (1983). *Principles of Underwater Sound*.
  McGraw-Hill.
- ISO 17208-1. *Underwater Acoustics: Quantities and procedures
  for description and measurement of underwater sound from ships*.

## License

Apache-2.0.
