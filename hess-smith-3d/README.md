# yard-hess-smith-3d-zig

Proof level: `unit-tested`

yard-hess-smith-3d-zig is a Zig 0.16 3D source-distribution panel
method using a point-source-at-centroid approximation. Allocator-free;
caller supplies the N x N influence matrix and RHS buffers. Includes
a lat-lon sphere mesh generator and sphere-Cp validation.

## What it does

- `hess_smith_3d.Panel` typed struct (centroid, outward normal, area).
- `hess_smith_3d.assemble(panels, Ux, Uy, Uz, A, b)` builds the
  influence matrix using centroid-source influence.
- `hess_smith_3d.gaussSolve(A, b, n)` in-place Gauss elimination with
  partial pivoting; explicit `SingularMatrix` error.
- `hess_smith_3d.velocityAt(panels, i, sigma, Ux, Uy, Uz)` recovers
  the 3D velocity at a panel centroid.
- `hess_smith_3d.pressureCoefficient(...)` returns
  `1 - |V|^2 / |U|^2` at a centroid.
- `sphere_mesh.unitSphere(n_lat, n_lon, out)` produces a lat-lon
  discretization of the unit sphere.

## What it is not (v0.0.0)

- No closed-form Hess-Smith 1964 polygon influence integration
  (centroid-source approximation is used; first-order accurate).
- No lifting (Kutta condition) extension.
- No free-surface Green function.
- No FMM or Krylov solver (Gauss elimination is O(N^3)).
- No general-mesh ingest (only the sphere generator is supplied).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 9/9 tests passed`.

## Public API

```zig
const yard = @import("yard_hess_smith_3d");
const hs = yard.hess_smith_3d;
const sm = yard.sphere_mesh;

const N_lat: usize = 12;
const N_lon: usize = 16;
const N: usize = N_lat * N_lon;
var panels: [N]hs.Panel = undefined;
_ = sm.unitSphere(N_lat, N_lon, &panels);

var A: [N * N]f64 = undefined;
var b: [N]f64 = undefined;
try hs.assemble(&panels, 1.0, 0.0, 0.0, &A, &b);
try hs.gaussSolve(&A, &b, N);
// b now holds the source-strength vector sigma.

const cp = hs.pressureCoefficient(&panels, some_panel_index, &b, 1.0, 0.0, 0.0);
```

## Validation

- Self-influence (panel induces on itself) returns 0.5 to f64 round-off.
- Gauss elimination on 3x3 identity returns the RHS unchanged.
- Singular-matrix rejection.
- Buffer-size mismatch rejection.
- Unit-sphere total area approximates 4 pi to f64 round-off.
- Unit-sphere panel centroids lie on the unit sphere to f64 round-off.
- 12 x 16 = 192-panel sphere in uniform flow returns Cp at side
  (analytical -5/4) within 0.5. The centroid-source approximation
  converges linearly; finer meshes tighten the bound.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Hess, J.L. and Smith, A.M.O. (1964), "Calculation of nonlifting
  potential flow about arbitrary three-dimensional bodies,"
  Journal of Ship Research 8(2): 22-44.
- Newman, J.N. (1977), *Marine Hydrodynamics*, MIT Press, Ch. 6.
- Codex cross-references at `~/codex/concepts/hess-smith-panel-method.md`.

## License

AGPL-3.0-or-later.
