# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `gz.smallAngleGZ`, `gz.wallSidedGZ` GZ righting-arm computation.
- `gz.rectTankIfs`, `gz.fsContribution`, `gz.effectiveGM` free-surface
  correction primitives.
- `damage.boxBargeOneCompartment` lost-buoyancy damaged-condition
  waterline for an N-equal-compartment box-barge with one flooded
  compartment and permeability mu.
- `damage.boxBargeIntactIT` intact transverse moment of inertia of
  the damaged-condition waterplane.
- `is_code.evaluate` IMO 2008 IS Code Part A 2.2 numerical criteria
  evaluator with trapezoidal GZ-area integration.
- 19-test unit suite including cross-checks against validation_fixtures
  box-barge values.
- Bench step measuring wallSidedGZ and is_code.evaluate latency.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

## [0.1.0] 2026-05-30

Deepening release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `kn` module: KN cross-curves of stability + full GZ-curve
  reconstruction via `GZ(phi) = KN(phi) - KG sin(phi)`.
- `kn.standard_angles_deg` IMO IS Code 9-point angle grid.
- `kn.gzFromKN`, `buildGZArrayM` per-point and array forms.
- `kn.gzAtAngleM` linear interpolation off-grid with endpoint
  clamping.
- `kn.maxGZM`, `angleOfMaxGZDeg` peak diagnostics.
- `kn.rangeOfStabilityDeg` linear zero-crossing interpolation.
- `kn.dynamicStabilityMRad` Simpson 1/3 quadrature with
  trapezoidal fallback for partial ranges.
- 15 unit tests including KN -> GZ formula, off-grid linear
  interpolation, endpoint clamping, triangular-GZ Simpson area
  match against the analytical 0.5 b h, linear scaling with peak
  GZ, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
