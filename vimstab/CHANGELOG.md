# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `container_stack.totalStackMassKg` per-tier mass sum.
- `container_stack.lateralAccelerationMPS2` g sin phi + a_y_cg.
- `container_stack.lateralForceN` m a_lat.
- `container_stack.rackingDeflectionM` F / k.
- `container_stack.deflectionVerdict` pass / fail vs permissible.
- 15-test unit suite including 60 t stack, g/2 at 30 deg, 180 kN
  force, 18 mm deflection, inclusive-boundary verdict, and
  typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
