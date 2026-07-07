# Status

yard-fossen-6dof-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `fossen.State` typed struct | `unit-tested` | Used in every other test |
| `fossen.Parameters` typed struct | `unit-tested` | Used in every other test |
| `fossen.rk4Step` | `unit-tested` | Zero in -> zero out; surge step accelerates; surge converges toward tau/D_lin within 1 percent over 5000 s; heave restoring + damping reduces displacement; decoupled channels (linearized); roll damped oscillation; impulsive limit matches tau h / M within 1e-4; rejects non-positive step and non-positive M |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `11/11 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## What is not covered (v0.0.0)

- Nonlinear C(nu) and D(nu).
- Off-diagonal added mass.
- Quaternion attitude.
- Environmental forcing.

## Validation against codex substrate

Formulation traces to
`~/codex/concepts/fossen-6dof-maneuvering-model.md`.
