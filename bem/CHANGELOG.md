# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `hess_smith_2d.Panel` typed struct with centroid, length, tangent,
  outward normal.
- `hess_smith_2d.buildPanel` constructor with zero-length rejection.
- `hess_smith_2d.assemble` influence-matrix builder; caller-allocated
  buffers; no heap.
- `hess_smith_2d.gaussSolve` in-place Gauss elimination with partial
  pivoting and explicit singular-matrix rejection.
- `hess_smith_2d.tangentialVelocity` and
  `hess_smith_2d.pressureCoefficient` surface-quantity recovery.
- 8-test unit suite including the classical 2D circle validation
  with N = 64 panels.
- Bench step at N = 16, 32, 64.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
