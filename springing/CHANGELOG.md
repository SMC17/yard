# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `hull_girder.twoNodeBendingHz` Schlick formula.
- `hull_girder.phi_schlick_merchant_si` 32000 SI coefficient.
- `hull_girder.twoNodeBendingRps`, `twoNodePeriodSec`.
- `whipping.dampedAngularFrequencyRps`, `freeDecayAmplitude`,
  `logarithmicDecrement`.
- 18-test unit suite including Schlick scaling laws, envelope
  monotonicity, and damped-frequency closed forms.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

Schlick coefficient phi flagged `claimed`; per-ship calibration
deferred.
