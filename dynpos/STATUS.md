# Status

yard-dynpos-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `allocation.allocate` | `unit-tested` | three-thruster surge / yaw / sway cases close within 1 N; four-thruster DP-2 redundant case closes |
| `allocation.closingResidual` | `unit-tested` | tau_actual = B u recovers tau within 1 N on well-posed cases |
| `allocation.max_thrusters` | `unit-tested` | stack-buffer ceiling 8 |
| singular-matrix detection | `unit-tested` | colinear longitudinal thrusters trigger Error.SingularConfigurationMatrix |
| `telemetry_protocol` | `unit-tested` | strict state encode and command parse/validation under `yard.telemetry.v1` |
| `nats_telemetry` | `integration-tested` locally | Zig state publisher -> local NATS -> ArmadaClaw -> local NATS -> Zig command subscriber, 100/100 correlated messages |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `15/15 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: pseudo-inverse allocation only; the
  kernel does not claim feasibility under thrust-limit saturation.
  The closing-residual diagnostic flags when the underlying B B^T
  inversion is well-posed; singular configurations return a typed
  error rather than producing NaN thrusts.
- Type-II missed risk guard: 1e-18 determinant threshold on the
  3x3 BBT prevents silent overflow on degenerate geometries.
- Type-III category guard: steady-state minimum-energy allocator
  only; not a power-management engine; not a thrust-limit QP solver;
  not a DP-2 / DP-3 reconfiguration ledger; not a wave-feedforward
  controller.

## What is not covered (v0.0.0)

- Azimuthing-thruster steering optimisation.
- Thrust saturation / quadratic programming.
- Power management / blackout reconfiguration.
- DP-2 / DP-3 fault-tolerance reconfiguration.
- Wave / wind feedforward control.
- Authenticated/TLS NATS, broker failover, cross-host OTP partitions, and HIL
  timing remain unmeasured.

## Composition

- Thruster geometry inputs from a vessel-level lever-arm catalogue
  (the `(alpha_i, x_i, y_i)` triple per propulsor).
- Demand `tau` from a DP controller; the steady-state allocator sits
  inside the controller's inner loop.
- Output `u_out` feeds saturation / rate-limit logic before
  reaching the per-thruster servo loop.
