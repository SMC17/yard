# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `motion.HelideckClass` enum, `MotionLimits` typed struct.
- `motion.limitsForClass` table lookup.
- `motion.lateralAccelerationFromRollMPS2` phi_dd * h.
- `motion.inclinationDeg` sqrt(pitch^2 + roll^2).
- `motion.envelopeVerdict` combined pass / fail.
- 14-test unit suite including class-ordering, Pythagorean
  inclination, per-axis fails, combined-inclination fail at
  individually-passing axes, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

Motion-limit table flagged `claimed`; verify against helicopter-
operator MEL before regulatory use.
