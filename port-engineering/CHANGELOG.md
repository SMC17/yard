# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `breakwater.transmissionCoefficient` Goda-Ahrens K_t.
- `breakwater.hudsonMedianWeightKg` rho_s g H^3 / (K_D (S-1)^3 cot alpha).
- `breakwater.iribarrenNumber`, `runupHeightHuntM`.
- `channel.UkcLevel` (exposed 0.20 / inner 0.10 / dock 0.05).
- `channel.requiredUKCM`, `squatBarrassM`, `grossChannelDepthM`.
- `channel.ManoeuvringClass` (good 1.8 / moderate 2.0 / difficult 2.5).
- `channel.twoWayChannelWidthM` PIANC formula.
- `basin.helmholtzPeriodSec` coupled basin-channel.
- `basin.seichePeriodClosedClosedSec`, `seichePeriodClosedOpenSec`
  Merian formula.
- `basin.resonanceVerdict` 5 % resonance band.
- 40-test unit suite covering large-free-board K_t -> 0, Hudson H^3
  and 1/K_D scaling, Iribarren plunging vs surging, PIANC UKC
  ordering, Barrass V^2.08 squat, Helmholtz sqrt(A) scaling,
  seiche mode-2 = half mode-1, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
