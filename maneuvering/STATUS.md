# Status

yard-maneuvering-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `nomoto.nomotoFirstOrderYawRate` | `unit-tested` | Zero at t=0; equals (1-1/e) K delta_0 at t=T within 0.1 percent; equals K delta_0 at large t to f64 round-off; monotonically increasing for positive K and delta_0; sign-flips with delta_0 |
| `nomoto.nomotoFirstOrderHeading` | `unit-tested` | Zero at t=0; equals K delta_0 (t - T) at large t within 0.1 percent; linear scaling with delta_0 |
| `nomoto.nomotoSteadyStateYawRate` | `unit-tested` | Algebraic identity used by other tests |
| `nomoto.firstOrderTFromSecondOrder` | `unit-tested` | Algebraic identity check |
| `nomoto.nomotoSecondOrderYawRate` | `unit-tested` | Zero at t=0; converges to K delta_0 at large t; double-root case T1=T2 handled separately; small-T2 limit approaches steady state at finite t |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `15/15 tests pass`.

```
zig build test --summary all
```

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: t = T 63 percent property is the canonical
  textbook check, tested to 0.1 percent. Larger tolerance would be
  meaningless; tighter would test floating-point arithmetic, not the
  model.
- Type-II missed risk guard: explicit error variants for non-positive
  time constants.
- Type-III category guard: this is a first / second-order linear yaw
  model. Not a 6-DOF simulator, not a thrust-allocation engine, not
  an autopilot.

## What is not covered (v0.0.0)

- Rudder-rate input (T3 delta_r_dot term zero for step input;
  non-step inputs require explicit handling).
- Full Fossen 6-DOF.
- Dynamic positioning thrust allocation.
- Zig-zag maneuver simulator.

## Validation against codex substrate

Formulas trace to `~/codex/concepts/nomoto-maneuvering-model.md`.
