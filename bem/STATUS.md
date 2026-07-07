# Status

yard-bem-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `hess_smith_2d.buildPanel` | `unit-tested` | Zero-length rejection; correct length and tangent on a 3-4-5 panel |
| `hess_smith_2d.assemble` | `unit-tested` | Buffer-size validation; used in the circle validation test |
| `hess_smith_2d.gaussSolve` | `unit-tested` | 3x3 identity preservation; known small system solved correctly; singular matrix rejection |
| `hess_smith_2d.tangentialVelocity` | `unit-tested` | Used in the circle validation test |
| `hess_smith_2d.pressureCoefficient` | `unit-tested` | Circle: Cp at rear stagnation panel within 0.1 of analytical 1.0; Cp at top panel within 0.5 of analytical -3.0; with N = 64 panels |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `8/8 tests pass`.

```
zig build test --summary all
```

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: circle tolerances are 0.1 (stagnation) and
  0.5 (top), reflecting the geometric panel-discretization error at
  N = 64. Tighter would require more panels and is not asserted.
- Type-II missed risk guard: explicit error variants for degenerate
  panels, buffer-size mismatch, singular matrix, insufficient panel
  count.
- Type-III category guard: 2D non-lifting only. No Kutta condition
  for lifting bodies. No free-surface Green function. No 3D extension.

## What is not covered (v0.0.0)

- 3D Hess-Smith.
- Lifting formulation (Kutta condition).
- Free-surface Green function.
- Higher-order panels.
- Krylov / FMM solvers (Gauss elimination is O(N^3); usable only at
  modest N).

## Validation against codex substrate

Formulation traces to `~/codex/concepts/hess-smith-panel-method.md`.
