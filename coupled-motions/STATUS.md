# Status

yard-coupled-motions-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `coupled.Complex` | `unit-tested` | add/sub/mul/abs against closed-form; div against (1+2i)/(3+4i) = (11/25, 2/25) |
| `coupled.solveRAO` | `unit-tested` | Identity Z gives X = F; diagonal matrices match 1-DOF closed form; off-diagonal coupling produces cross-DOF response; low-omega gives C^-1 F; high-omega gives zero; resonance peaks > 10x off-resonance; singular impedance detected |
| `coupled.raoMagnitudes` | `unit-tested` | modulus of (3,4) = 5; (0,5) = 5; (-8,6) = 10 |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `12/12 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: `solveRAO` returns `Error.SingularMatrix`
  when the impedance is degenerate. The solver does not silently
  produce NaN responses.
- Type-II missed risk guard: explicit complex Gauss elimination with
  partial pivoting; ill-conditioned matrices propagate to a singular
  detection rather than a silent overflow.
- Type-III category guard: frequency-domain steady-state solver only;
  not a time-domain integrator (use `yard-fossen-6dof-zig`); not a
  hydrodynamic-coefficient calculator (use `yard-bem-zig`,
  `yard-hess-smith-3d-zig`).

## What is not covered (v0.0.0)

- General N-DOF coupled motion.
- Frequency-dependent `A(omega)`, `B(omega)` lookup.
- Forward-speed encounter-frequency mapping.
- Nonlinear viscous roll damping (Ikeda).
- Direct spectrum-to-response convolution (compose with
  `yard-rao-spectrum-zig`).

## Composition

- Input `A`, `B`, `C` matrices can be sourced from `yard-strip-theory-zig`
  (heave/pitch via strip theory) plus a roll-damping model.
- Output `X` per `omega` composes with `yard-rao-spectrum-zig` to
  produce significant response amplitude across a sea state.
