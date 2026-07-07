# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `nomoto.nomotoFirstOrderYawRate` analytical first-order step
  response.
- `nomoto.nomotoFirstOrderHeading` integrated heading.
- `nomoto.nomotoSteadyStateYawRate` convenience.
- `nomoto.firstOrderTFromSecondOrder(T1, T2, T3)` identity.
- `nomoto.nomotoSecondOrderYawRate` closed-form second-order step
  response with separate double-root handling.
- 15-test unit suite including the canonical t = T 63-percent
  property and monotonicity / sign-flip checks.
- Bench step.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
