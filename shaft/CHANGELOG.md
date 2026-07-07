# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `holzer.holzerResidual` free-free Holzer table.
- `holzer.findNaturalFrequency` bracketed bisection.
- `shaft_stiffness.polarSolidM4`, `polarHollowM4`.
- `shaft_stiffness.torsionalStiffnessNmPerRad`.
- `shaft_stiffness.polarMassInertiaSolidKgm2`.
- 19-test unit suite including two-inertia analytic check, residual
  sign-change verification, three-inertia bracket, D^4 scaling, and
  typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
