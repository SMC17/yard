# yard-mooring-zig

Proof level: `unit-tested`

yard-mooring-zig is a Zig 0.16 static catenary cable kernel for
inextensible mooring lines suspended between an anchor (assumed at
the catenary low point) and a fairlead. Closed-form catenary
relations: shape, arc length, tangent angle, tension magnitude at
arbitrary horizontal position, and inverse solve for horizontal force
given fairlead offsets.

## What it does

- `catenary.catenaryParameterM(H, w)` returns the catenary scale
  `a = H / w`.
- `catenary.catenaryY(a, x)` returns the catenary shape
  `y(x) = a (cosh(x/a) - 1)` with the low point at the origin.
- `catenary.arcLengthM(a, x)` returns the arc length from the low
  point: `s(x) = a sinh(x/a)`.
- `catenary.tensionAtXN(H, a, x)` returns `T(x) = H cosh(x/a)`.
- `catenary.verticalForceN(H, a, x)` returns `V(x) = H sinh(x/a) = w s(x)`.
- `catenary.tangentAngleRad(a, x)` returns `atan(sinh(x/a))`.
- `catenary.solveHorizontalForceFromXYN(x, y, w)` inverse solves
  `a (cosh(x/a) - 1) = y` via bisection (monotonic in `a`).

## What it is not (v0.0.0)

- No multi-segment / sea-bed-touchdown catenary (caller adds the
  grounded-portion length externally).
- No elastic stretch (axial stiffness EA).
- No dynamic mooring (frequency / time-domain response to vessel
  motion).
- No hydrodynamic / current drag on the line.
- No multi-line mooring matrix assembly.
- No MBL / safety-factor verdict (caller wraps with API RP 2SK
  permissible-tension ratios externally).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 17/17 tests passed`.

## Public API

```zig
const yard = @import("yard_mooring");

const H: f64 = 1.0e6;  // [N]
const w: f64 = 100.0;  // [N/m] submerged weight per unit length
const a = try yard.catenary.catenaryParameterM(H, w);
const x: f64 = 50.0;   // [m] horizontal distance from low point
const y = yard.catenary.catenaryY(a, x);
const s = yard.catenary.arcLengthM(a, x);
const T = yard.catenary.tensionAtXN(H, a, x);
const V = yard.catenary.verticalForceN(H, a, x);
const theta = yard.catenary.tangentAngleRad(a, x);

// Inverse: solve for H given the fairlead offset (x, y) and w.
const H_solved = try yard.catenary.solveHorizontalForceFromXYN(x, y, w);
```

## Validation

- `a = H / w` closed form to 1e-12.
- `y(0) = 0`, `s(0) = 0`, `theta(0) = 0` at the low point.
- `y(a) = a (cosh 1 - 1) ~= 0.5431 a` to 1e-6.
- `T(0) = H`; `T(x)` strictly monotone in x.
- `T(x) = H + w y(x)` identity (energy form) to 1e-9.
- `s(x) > x` (arc exceeds chord) for nonzero x.
- `V(x) = w s(x)` to 1e-9.
- `theta = pi/4` when `x = a asinh(1)`.
- Inverse solve recovers the forward `H` to 1e-4 relative over four
  decades of `H/w` ratios.
- Typed-error rejection for non-positive `H`, `w`, `x`, `y`.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Faltinsen, O. (1990). *Sea Loads on Ships and Offshore Structures*.
  Cambridge.
- Berteaux, H. (1976). *Buoy Engineering*. Wiley-Interscience.
- API Recommended Practice 2SK. *Design and Analysis of Stationkeeping
  Systems for Floating Structures*.
- DNV-OS-E301. *Position Mooring*.

## License

Apache-2.0.
