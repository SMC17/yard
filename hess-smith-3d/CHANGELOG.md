# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `hess_smith_3d.Panel` typed panel struct (centroid, normal, area).
- `hess_smith_3d.assemble` influence-matrix builder.
- `hess_smith_3d.gaussSolve` in-place Gauss elimination with partial
  pivoting and singular-matrix rejection.
- `hess_smith_3d.velocityAt` and
  `hess_smith_3d.pressureCoefficient` surface-quantity recovery.
- `sphere_mesh.unitSphere` lat-lon discretization.
- 9-test unit suite including the classical sphere validation with
  192 panels.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
