# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `sn.DetailClass` enum of fourteen DNV-RP-C203 in-air detail classes.
- `sn.kneeStressMPa` knee-point stress at log N = 7.
- `sn.cyclesToFailure` bilinear log-log S-N evaluation with
  thickness reduction (t / t_ref)^k for t > t_ref.
- `miner.cumulativeDamage` Palmgren-Miner sum.
- `miner.verdict` pass/fail at unit-damage threshold.
- `miner.remainingLifeFromCurrentBlock` linear-repetition
  extrapolation.
- 20-test unit suite including closed-form S-N matching, class
  ordering, thickness scaling, and Miner sum threshold logic.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

S-N parameter table transcribed from DNV-RP-C203 (air); independent
re-verification not yet performed. Proof level `claimed` for the
table itself, `unit-tested` for the evaluation logic.
