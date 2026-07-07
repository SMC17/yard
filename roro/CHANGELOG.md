# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `deck_load.apparentWeightN` m (g + a_v).
- `deck_load.lateralLashingForceN` m (a_h + g sin phi).
- `deck_load.apparentGravityTiltRad` atan2-based tilt of the
  apparent-gravity vector.
- `deck_load.tippingAngleRad` atan(b / (2 h_cg)).
- `deck_load.tippingVerdict` pass / fail vs tipping angle.
- 16-test unit suite including rest weight, vertical-accel scaling,
  pure roll lashing, narrow-tall vehicle tipping geometry, and
  typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
