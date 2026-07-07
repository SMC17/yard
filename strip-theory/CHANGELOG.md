# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `heave.Complex` typed complex number with magnitude method.
- `heave.responseAmplitude` frequency-domain solver.
- `heave.raoModulus` heave RAO modulus.
- `heave.naturalFrequency` undamped natural frequency.
- 12-test unit suite covering long-wave limit, natural-frequency
  peak, high-frequency decay, phase-independence, |F| linearity,
  and input rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
