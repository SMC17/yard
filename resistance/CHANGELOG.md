# Changelog

Format roughly follows Keep-a-Changelog. Semver bound by
`~/CONVENTIONS.md` C2 (pre-1.0 while Zig is pre-1.0).

## [0.1.0] 2026-05-30

Deepening release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `holtrop_extended` module with the full Holtrop-Mennen 1984
  coefficient chain.
- `holtrop_extended.c1Coefficient` 2 223 105 * c_7^3.78613 *
  (T/B)^1.07961 * (90 - i_E)^-1.37565.
- `holtrop_extended.c5Coefficient` transom-immersion correction
  1 - 0.8 A_T / (B T C_M).
- `holtrop_extended.c15Coefficient` L^3 / V branch interpolation.
- `holtrop_extended.c16Coefficient` two-branch C_P regression.
- `holtrop_extended.m1Coefficient`, `m3Coefficient`,
  `m4Coefficient` HM 1984 wave-resistance shape parameters.
- `holtrop_extended.lambdaParameter` L/B branch.
- `holtrop_extended.AppendageType` enum with HM 1984 Table 5
  (1 + k_2) values for eight common appendages; weighted-average
  equivalent form factor.
- `holtrop_extended.appendageResistanceN` 0.5 rho V^2 C_F (1+k_2)
  S_app.
- `holtrop_extended.roughnessAllowanceShort`,
  `roughnessAllowanceFull` model-ship correlation allowance C_A
  with optional bulb-correction term.
- `holtrop_extended.waveResistanceCoefficient` full HM C_W
  evaluator with low-Fn / high-Fn branch selection.
- 28 additional unit tests covering c_1 closed form, c_5 transom
  limit, c_15 three-branch step, c_16 sub-/super-0.80 C_P branch,
  m_1 / m_3 closed-form checks, lambda L/B branch ordering,
  appendage form-factor weighted average, roughness allowance with
  and without bulb correction, and wave-resistance branch
  selection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `ittc57.cF` ITTC-57 friction coefficient.
- `ittc57.rFPerArea` frictional resistance per unit wetted surface.
- `ittc57.reynolds` Reynolds-number convenience.
- `holtrop.HullParticulars` typed input struct.
- `holtrop.Environment` typed environment struct with seawater defaults.
- `holtrop.formFactor1984` Holtrop 1984 reanalysis (1 + k1).
- `holtrop.halfAngleOfEntrance` i_E per Holtrop 1982/1984.
- `holtrop.waveResistance` three-branch wave-resistance evaluator
  (low-Fn, high-Fn c17/m3, and the 0.4 to 0.55 linear blend).
- `holtrop.totalResistance` R_F (1+k) + R_W with a typed breakdown
  struct.
- 21-test unit suite covering ITTC-57 textbook values, monotonicity,
  sign behavior, transition continuity, c_stern directional check,
  and a regression lock at V = 6 m/s on a representative cargo fixture.
- `zig build bench -Doptimize=ReleaseFast` measuring per-call latency
  of cF, formFactor1984, and totalResistance.

### Coefficient verification posture

c17, m3 cross-verified against FreeCAD-Ship Holtrop.py and
aletirelli/holtrop-mennen Python implementation. Both cite Holtrop
1984 ISP 31 page 273 directly. Primary paper still blocked at IOS
Press; cross-implementation agreement is the verification we have.

c1, m1, m4, lambda, c14, c15, c16, c7 cross-verified against three
independent Python implementations (aletirelli/holtrop-mennen,
KZABORSKI/PyMarine-UoS, rpipeau3d/Sim.B.A.D).

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Bench environment

Numbers in README reflect a laptop with load average 5-64 during
measurement.
