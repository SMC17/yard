# Status

yard-hess-smith-3d-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `hess_smith_3d.influenceNormalVel` self-term | `unit-tested` | Returns 0.5 to f64 round-off |
| `hess_smith_3d.assemble` | `unit-tested` | Buffer-size mismatch rejection |
| `hess_smith_3d.gaussSolve` | `unit-tested` | 3x3 identity invariant; singular-matrix rejection |
| `hess_smith_3d.velocityAt`, `hess_smith_3d.pressureCoefficient` | `unit-tested` | Used in the sphere validation |
| Sphere validation (192-panel lat-lon) | `unit-tested` | Cp at the side (analytical -5/4) is negative and within 0.5; centroid-source approximation converges linearly with sqrt(N) |
| `sphere_mesh.unitSphere` | `unit-tested` | Panel count matches n_lat * n_lon; total area approximates 4 pi to f64 round-off; centroids lie on the unit sphere |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `9/9 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: sphere tolerance is 0.5 on Cp at N = 192
  because the centroid-source approximation converges linearly, not
  quadratically. Tighter would require either closed-form polygon
  integration (Hess-Smith 1964 appendix) or much finer meshes.
- Type-II missed risk guard: explicit error variants for buffer-size
  mismatch, singular matrix, insufficient panel count.
- Type-III category guard: source-only 3D. No Kutta condition for
  lifting bodies. No free-surface Green function. No 2D extension
  (use yard-bem-zig for the 2D source method).

## What is not covered (v0.0.0)

- Closed-form polygon influence integration (Hess-Smith 1964 appendix).
- Kutta condition for lifting bodies.
- Free-surface Green function.
- General-mesh ingest (currently only the sphere generator is provided).

## Validation against codex substrate

Formulation traces to `~/codex/concepts/hess-smith-panel-method.md`.
