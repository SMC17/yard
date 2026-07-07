# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `bollard.TugType` enum (Conventional / ASD / VSP / Escort).
- `bollard.bollardCoefficient`, `bollardPullKN`,
  `bollardPullCustomKN`, `bollardPullToTonnesForce`,
  `thrustToWeightRatio`.
- `indirect.effectiveForceKN`, `steeringMomentKNm`,
  `brakingForceKN`.
- `effective.bollardAtSpeedKN`, `typicalVMaxMPerS`,
  `assistanceVerdict`.
- 33-test unit suite including four tug-type coefficient ordering,
  linear power scaling, indirect-force decomposition, steering
  moment, braking-force closed form, speed-dependent degradation,
  and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

Bollard coefficients and V_max values flagged `claimed`; supplier-
specific data should override.
