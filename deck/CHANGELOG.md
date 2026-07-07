# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `crane.heelingMomentNm` SWL g r.
- `crane.swlFromChart` piecewise-linear interpolation with clamping.
- `crane.swlMomentLimit` hyperbolic-tip moment-limit chart.
- `tipping.rightingMomentNm` Delta g GM sin(phi).
- `tipping.equilibriumHeelRad` inverse balance.
- `tipping.tippingVerdict` pass / fail.
- `dynamic.dynamicAmplificationFactor` 1 + a_v / g.
- `dynamic.dynamicLoadN` SWL g DAF.
- `dynamic.waveDrivenAccelerationMPS2` indicative envelope.
- `dynamic.deratedSWL` SWL / DAF.
- 35-test unit suite including SWL chart interpolation,
  moment-limit hyperbola, tipping inverse-balance, DAF closed form,
  wave-acceleration scaling, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

`waveDrivenAccelerationMPS2` indicative envelope flagged `claimed`.
