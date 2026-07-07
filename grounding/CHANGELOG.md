# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `pedersen_zhang.kineticEnergyJ` with longitudinal added-mass
  correction.
- `pedersen_zhang.meanHorizontalForceN` smooth-rock mean force.
- `pedersen_zhang.C_g_smooth_rock` shape factor 1.62.
- `pedersen_zhang.dampageLengthM` E/F energy-force balance.
- `pedersen_zhang.GroundingInputs`, `GroundingResult` typed structs.
- `pedersen_zhang.analyseGrounding` three-step composer.
- 12-test unit suite including 189 MJ kinetic case, 15.228 MN
  horizontal-force case, V^2 damage-length scaling, and typed-
  error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

C_g = 1.62 is the smooth-rock value; sharp / blunt asperity
regimes require external lookup. The `claimed` proof level flags
the parameter, not the formula.
