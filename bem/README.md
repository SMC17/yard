# yard-bem-zig

Proof level: `unit-tested`

yard-bem-zig is a Zig 0.16 implementation of the 2D Hess-Smith non-
lifting source-distribution panel method. Discretize a closed 2D body
into N flat panels; build the N x N influence matrix; solve via Gauss
elimination with partial pivoting; recover surface tangential velocity
and pressure coefficient.

## What it does

- `hess_smith_2d.Panel` typed struct with centroid, length, tangent,
  outward normal.
- `hess_smith_2d.buildPanel(x1, y1, x2, y2)` constructor with
  zero-length rejection.
- `hess_smith_2d.assemble(panels, U_inf, V_inf, A, b)` builds the
  influence matrix and freestream RHS. Caller-allocated buffers; no
  heap.
- `hess_smith_2d.gaussSolve(A, b, n)` in-place Gauss elimination with
  partial pivoting; explicit `SingularMatrix` error.
- `hess_smith_2d.tangentialVelocity` and
  `hess_smith_2d.pressureCoefficient` recover the surface quantities.

## What it is not (v0.0.0)

- No 3D Hess-Smith.
- No lifting (Kutta condition) extension.
- No free-surface Green function (no waves).
- No higher-order panels.
- No GMRES or FMM solver (Gauss elimination is O(N^3)).
- No grid generator (caller supplies panel endpoints).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 8/8 tests passed`.

## Bench

```
zig build bench -Doptimize=ReleaseFast
```

Sample numbers from a laptop with high background load:

```
assemble+solve circle N=16      iters=5000    us/call=   40.9
assemble+solve circle N=32      iters=2000    us/call=  215.5
assemble+solve circle N=64      iters=500     us/call=  755.4
```

Cost scales roughly as N^3 (Gauss elimination dominates at this size).

## Public API

```zig
const yard = @import("yard_bem");

// Discretize a unit circle into 64 panels traced clockwise.
const N: usize = 64;
var panels: [N]yard.hess_smith_2d.Panel = undefined;
for (panels[0..], 0..) |*p, k| {
    const t1 = -@as(f64, @floatFromInt(k)) * 2.0 * std.math.pi / N;
    const t2 = -@as(f64, @floatFromInt(k + 1)) * 2.0 * std.math.pi / N;
    p.* = try yard.hess_smith_2d.buildPanel(@cos(t1), @sin(t1), @cos(t2), @sin(t2));
}

var A: [N * N]f64 = undefined;
var b: [N]f64 = undefined;
try yard.hess_smith_2d.assemble(&panels, 1.0, 0.0, &A, &b);
try yard.hess_smith_2d.gaussSolve(&A, &b, N);
// b now holds the source strengths sigma.

const cp = yard.hess_smith_2d.pressureCoefficient(&panels, 32, &b, 1.0, 0.0);
```

## Validation

The classical test for a 2D source-only panel method is uniform flow
past a circle. Analytical Cp on the surface is

```
C_p = 1 - 4 sin^2(theta)
```

with stagnation Cp = 1 at theta = 0 and theta = pi, and Cp = -3 at
theta = pi / 2.

With N = 64 panels, the source-only Hess-Smith implementation here:

- Recovers stagnation Cp = 1 within 0.1 at the rear stagnation panel.
- Recovers Cp = -3 within 0.5 at the top-of-circle panel.

These tolerances reflect the geometric panel-discretization error;
finer N converges roughly linearly toward the analytical values for
the source-only formulation on a smooth body.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0). Strongest
available claim: `stable-on-zig-0.16-today`.

## References

- Hess, J.L. and Smith, A.M.O. (1964), "Calculation of nonlifting
  potential flow about arbitrary three-dimensional bodies,"
  Journal of Ship Research 8(2): 22-44.
- Katz, J. and Plotkin, A. (2001), *Low-Speed Aerodynamics*, 2nd ed.,
  Cambridge UP, Ch. 11. The 2D panel-influence formulation used here.
- Newman, J.N. (1977), *Marine Hydrodynamics*, MIT Press, Ch. 6.
- Codex cross-references at `~/codex/concepts/hess-smith-panel-method.md`.

## License

AGPL-3.0-or-later.
