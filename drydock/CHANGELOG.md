# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `blocks.averagePerBlockN`, `nonUniformReactionsN`,
  `peakReactionN`, `totalReactionN`.
- `pressure.BlockMaterial` enum (Softwood / Hardwood / Steel /
  Concrete).
- `pressure.allowablePressurePa`, `bearingPressurePa`,
  `pressureVerdict`, `requiredAreaM2`.
- `transverse.virtualGGRiseM` P KG / Delta.
- `transverse.residualGMM` initial - GG_v.
- `transverse.dockingStabilityVerdict` pass / fail at GM = 0.
- `transverse.criticalBlockForceN` W - B_residual with clamping.
- 38-test unit suite including uniform / non-uniform block reactions,
  material-pressure ordering, GG-rise scaling, docking-stability
  verdict, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

Material-pressure allowable values flagged `claimed`.
