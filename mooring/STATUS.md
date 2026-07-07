# Status

yard-mooring-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `catenary.catenaryParameterM` | `unit-tested` | a = H / w closed form |
| `catenary.catenaryY` | `unit-tested` | y(0) = 0; y(a) = a (cosh 1 - 1) closed form |
| `catenary.arcLengthM` | `unit-tested` | s(0) = 0; s > x for x > 0; V = w s identity |
| `catenary.tensionAtXN` | `unit-tested` | T(0) = H; strict monotone; T = H + w y identity |
| `catenary.verticalForceN` | `unit-tested` | V = w s consistency to 1e-9 |
| `catenary.tangentAngleRad` | `unit-tested` | theta(0) = 0; theta = pi/4 at x = a asinh(1) |
| `catenary.solveHorizontalForceFromXYN` | `unit-tested` | bisection inverse-solve recovers forward H to 1e-4 across four decades of H |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `17/17 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: bisection inverse solve is bracketed and
  guaranteed-monotonic; the solver returns `Error.NoConvergence` if
  the bracket cannot be established within 200 doublings of the
  upper bound, rather than silently returning a stale Newton step.
- Type-II missed risk guard: input rejection for non-positive H, w,
  x, y prevents downstream NaN / underflow propagation.
- Type-III category guard: static inextensible catenary kernel only;
  not a dynamic-mooring time-domain solver; not an FE cable model;
  not an MBL / safety-factor verdict engine.

## What is not covered (v0.0.0)

- Sea-bed-touchdown grounded portion (caller adds externally).
- Axial elasticity (EA stretch).
- Dynamic mooring (frequency / time domain).
- Hydrodynamic drag, current, vortex-induced vibration.
- Multi-line mooring spread matrix assembly.
- Code-specific permissible-tension ratios.

## Numerical regime caveat

For very large H / (w x) the catenary degenerates to a straight rope
and `cosh(x/a) - 1` loses double-precision significance. The
inverse-solve test range covers four decades of H / w; the solver
handles the degenerate regime via bisection rather than Newton.
