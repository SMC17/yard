# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `section_check.SteelGrade` enum with UR S4 material factor.
- `section_check.LoadingCondition` and `section_check.Section`
  typed inputs.
- `section_check.permissibleStressMpa` 175 / k computation.
- `section_check.evaluate` per-condition section-modulus check
  with typed Result.
- `section_check.aggregateVerdict` across multiple conditions.
- 11-test unit suite including Hughes/Paik-style bulker cross-check.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

## [0.1.0] 2026-05-30

Deepening release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `hull_girder` module: IACS CSR-H Section 5 wave-coefficient C
  (three-branch L envelope); hogging/sagging/horizontal wave
  bending moments; Section 6 ultimate-moment capacity gamma_M
  sigma_y Z; ultimate-strength verdict M_U >= gamma_S (M_sw + gamma_W
  M_wv).
- 17 new unit tests including three-branch C(L), L^2 scaling,
  hogging > 0 and sagging < 0, ultimate-moment linear scaling, and
  verdict at exact threshold.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
