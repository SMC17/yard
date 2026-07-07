# Status

yard-foilcraft-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `foil.liftN` | `unit-tested` | 51 250 N worked example; V^2 scaling |
| `foil.takeoffSpeedMPerS` | `unit-tested` | sqrt(W) and 1/sqrt(C_L) scaling |
| `foil.cavitationOnsetSpeedMPerS` | `unit-tested` | sqrt((p_0-p_v)/(0.5 rho |Cp|)) closed form |
| `foil.cavitationVerdict` | `unit-tested` | < boundary sub_cavitating; >= boundary cavitating |
| `foil.liftToDragRatio` | `unit-tested` | C_L / (C_D0 + C_L^2/(pi AR e)) closed form; surface-piercing > fully-submerged ordering |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `14/14 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: sub-cavitating regime only; the kernel
  flags V > V_cav but does not pretend to compute lift in the
  cavitating regime (super-cavitating section design is outside
  scope and listed under "what is not covered").
- Type-II missed risk guard: typed-error rejection for non-positive
  density / speed / area / lift coefficient / weight, p_v >= p_0.
- Type-III category guard: single-foil lift kernel only; not a
  super-cavitating section calculator; not a multi-foil arrangement
  optimiser; not a takeoff-dynamics integrator; not a flap-kinematic
  engine.

## What is not covered (v0.0.0)

- Super-cavitating section lift / drag.
- Multi-foil configuration.
- Flap / strut deployment kinematics.
- Water-jet propulsion coupling.
- Takeoff dynamics.
- Body-foil interaction induced drag.

## Composition

- Output `V_TO` couples to a `yard-resistance-zig` curve for the
  power required at take-off vs cruise.
- Cavitation gate composes with `yard-cavitation-zig` Burrill check
  for the propeller side of the propulsion train.
- Surface-piercing vs fully-submerged span efficiency feeds into the
  `liftToDragRatio` performance trade.
