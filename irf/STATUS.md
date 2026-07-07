# Status

yard-irf-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `cummins.retardationFunctionAtT` | `unit-tested` | constant-B closed form to 1e-9 on K(0); delta-bump matches (2/pi) B dw cos(omega_p t) approximation |
| `cummins.buildRetardationArray` | `unit-tested` | populates t grid; K(0) the largest magnitude entry |
| `cummins.addedMassInfinity` | `unit-tested` | zero-K identity returns A_at_ref |
| `cummins.cumminsStep` | `unit-tested` | ballistic, restoring, and memory cases match forward-Euler closed forms |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `12/12 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: trapezoidal quadrature is order h^2 in the
  omega grid; the kernel does not claim sub-percent accuracy on
  arbitrary B(omega). The retardation array is only as accurate as
  the input B grid sampling.
- Type-II missed risk guard: typed-error rejection for unequal-
  length, non-uniform spacing, unsorted omega, non-positive mass /
  step / omega_ref. The kernel does not silently truncate convergence
  failures.
- Type-III category guard: single-DOF time-domain kernel only; not
  a multi-DOF coupled solver (compose with
  `yard-coupled-motions-zig` for the equivalent frequency-domain
  approach); not a state-space realisation engine; not an
  FFT-accelerated K-computer.

## What is not covered (v0.0.0)

- FFT-based K(t) computation.
- Velocity-history convolution maintenance (caller does this).
- Prony / vector-fitting state-space realisation of K(t).
- Multi-DOF coupling.
- RK4 / higher-order integrators.

## Composition

- Input `B(omega)` from `yard-strip-theory-zig` heave or roll damping
  spectra.
- Output K array couples to a downstream RK4 integrator (the
  forward-Euler step here is intentionally minimal).
- A_infinity links to `yard-coupled-motions-zig` frequency-domain
  cross-check at omega_ref.
