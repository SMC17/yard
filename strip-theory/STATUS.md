# Status

yard-strip-theory-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `heave.Complex.mag` | `unit-tested` | sqrt(re^2 + im^2) on 3-4-5 |
| `heave.responseAmplitude` | `unit-tested` | At omega=0 returns F/C_33 real; rejects non-positive m_eff and C_33 |
| `heave.raoModulus` | `unit-tested` | Long-wave limit RAO -> 1 within 0.1 percent when F = C_33; equals |F|/(B_33 omega_n) at omega_n; peaks at omega_n; decays at high omega; independent of forcing phase; linear in |F| |
| `heave.naturalFrequency` | `unit-tested` | Match against direct sqrt evaluation |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `12/12 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## What is not covered (v0.0.0)

- 6-DOF coupled equations of motion.
- Per-station Lewis-form 2D added mass and damping.
- Forward-speed STF correction.
- Spectral-response convolution (compose externally with
  yard-seakeeping-zig).

## Validation against codex substrate

Formulation traces to
`~/codex/concepts/salvesen-tuck-faltinsen-strip-theory.md`.
