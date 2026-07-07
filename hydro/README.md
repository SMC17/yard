# yard-hydro-zig

Proof level: `unit-tested`

yard-hydro-zig is a Zig 0.16 library of foundational naval-architecture
hydrostatic primitives, validated against closed-form analytical hulls
(Wigley parabolic, rectangular box-barge).

## What it does

- **Composite Simpson 1/3 and Simpson 3/8** quadrature on precomputed
  ordinate arrays.
- **Wigley parabolic hull** with the canonical form
  `y(x, z) = (B/2) (1 - (2x/L)^2) (1 - (z/T)^2)` (z measured downward from
  waterline; Kajitani-Miyata 1983). Closed-form hydrostatic quantities:
  volume, waterplane area, KB, LCB, transverse and longitudinal moments
  of inertia, BM_T, BM_L, KM_T, KM_L, and the form coefficients C_B = 4/9,
  C_M = C_P = C_W = 2/3.
- **Rectangular box-barge** with closed-form hydrostatic quantities.
- **Hydrostatic integrators** consuming offset and ordinate tables: volume
  from sectional areas, waterplane area from half-breadths, transverse
  moment of inertia from half-breadths, LCB from sectional areas.

## What it is not

This is a substrate primitive. It is not a ship-design suite, not a CAD
tool, not a regulatory compliance harness. Downstream modules for
resistance prediction, seakeeping, hull-girder strength, and classification
compliance consume the integrators here and are out of scope for v0.0.0.

## Why the closed-form fractions matter

Wigley's hydrostatic quantities collapse to clean rationals in (L, B, T).
The block coefficient is exactly 4/9. The waterplane, midship, and
prismatic coefficients are exactly 2/3. The vertical center of buoyancy
is exactly 5T/8 above the keel. The transverse metacentric radius is
exactly 3B^2/(35T).

These are not approximations. A numerical integrator that returns
`C_B = 0.4445` instead of `4/9 = 0.4444...` is failing within rounding;
an integrator that returns anything further is wrong. The tests in this
library cross-check that:

1. Simpson 1/3 on the Wigley sectional-area ordinates (a degree-2
   polynomial in `x`) reproduces volume to f64 round-off, because
   Simpson 1/3 is exact for polynomials of degree at most 3.
2. The transverse moment of inertia integrand is degree 6; Simpson 1/3
   is not exact, and the error scales as O(h^4). The convergence test
   verifies that halving h reduces error by a factor of at least 8.

This is the foundation discipline: downstream kernels for resistance
prediction and stability evaluation only mean something if the
underlying integrators are right on the analytical case.

## Build and test

```
zig build test --summary all
```

Expected output:
```
Build Summary: 3/3 steps succeeded; 28/28 tests passed
```

## Bench

```
zig build bench -Doptimize=ReleaseFast
```

Sample numbers from a laptop with high background load (load average
12-64 during this run; numbers are upper bounds, not "best case"):

```
simpson13_wigley         N=11    iters=200000    ns/call=    40.2
simpson13_wigley         N=21    iters=200000    ns/call=    42.5
simpson13_wigley         N=41    iters=200000    ns/call=    67.0
simpson13_wigley         N=81    iters=200000    ns/call=   159.8
simpson13_wigley         N=161   iters=200000    ns/call=   263.6
simpson13_wigley         N=321   iters=200000    ns/call=   379.7
```

These numbers are with a per-iteration write to the ordinate buffer to
defeat constant-folding on loop-invariant input. The pattern matches
expected linear scaling in station count with cache-warmup at small N.

## Public API

```zig
const yard = @import("yard_hydro");

// Simpson's 1/3 on a precomputed ordinate array.
const v = try yard.simpson.simpson13(&ords, dx);

// Wigley hull, closed-form quantities.
const hull = yard.wigley.Hull{ .L = 100.0, .B = 10.0, .T = 4.0 };
const volume = hull.volume();         // (4/9) * L * B * T
const kb = hull.kb();                 // 5 * T / 8
const bm_t = hull.bmT();              // 3 * B^2 / (35 * T)

// Box-barge.
const barge = yard.box_barge.Barge{ .L = 10.0, .B = 4.0, .T = 1.5 };

// Numerical integration of waterplane half-breadths.
var ords: [21]f64 = undefined;
hull.waterlineOrdinates(0.0, &ords);
const a_w = try yard.integrate.waterplaneAreaFromHalfBreadths(&ords, hull.L / 20.0);
```

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: yard-hydro-zig depends on Zig 0.16. Until
Zig ships 1.0, no Zig project in the stax substrate can claim v1.0 in
semver spirit. The strongest available claim is
`stable-on-zig-0.16-today`.

## References

- Wigley parametric form and reference values: Kajitani, H. and Miyata, H.
  (1983), "Cooperative Experiment on Wigley Parabolic Models in Japan,"
  ITTC archive AD-P003 037.
- McCarthy, J. H. (1985), "Notes on the Wigley Hull," DTNSRDC.
- Box-barge worked example: Biran, A. and Lopez-Pulido, R. (2013),
  *Ship Hydrostatics and Stability*, 2nd ed., Butterworth-Heinemann,
  Ch. 10.
- Simpson's rule in naval architecture: Lewis, E. V. (ed.) (1988),
  *Principles of Naval Architecture*, Vol. I, SNAME, Ch. II.
- Closed-form derivations cross-checked against `~/codex/concepts/`
  notes for Simpson's rule, Bonjean curves, and GZ approximation,
  plus `~/codex/sources/validation_fixtures.md` and
  `~/codex/sources/hulls/wigley/parametric.md`.

## License

AGPL-3.0-or-later. See `LICENSE`.
