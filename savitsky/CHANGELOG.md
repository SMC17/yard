# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `savitsky.speedCoefficient` C_V = V / sqrt(g B).
- `savitsky.flatPlateLiftCoefficient` Savitsky 1964 C_L0.
- `savitsky.veeBottomLiftCoefficient` deadrise reduction.
- `savitsky.hydrodynamicLiftN` lift force.
- `savitsky.solveTrimDeg` bisection inverse trim-solver against
  displacement weight.
- 14-test unit suite including closed-form match, monotonicity,
  inverse force balance, and range-gate rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
