# Status

yard-launch-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `end_launch.slidingAccelerationMPS2` | `unit-tested` | g (sin alpha - mu cos alpha) closed form; 1:18 slipway value 0.2 - 0.5 m/s^2 |
| `end_launch.wayEndVelocityMPerS` | `unit-tested` | sqrt(2 a L); sqrt(L) scaling; negative a clamps to zero |
| `end_launch.wayEndKineticEnergyJ` | `unit-tested` | 0.5 m v^2; 3.6e8 J at 5000 t / 12 m/s |
| `end_launch.velocityFromGeometry` | `unit-tested` | composer reproduces composed call |
| `pivoting.buoyancyAtImmersionN` | `unit-tested` | linear in d_imm; zero at d_imm = 0 |
| `pivoting.sternLiftedOff` | `unit-tested` | true at exact threshold; false below; true above |
| `pivoting.forwardCradleReactionN` | `unit-tested` | lever rule: W/2 at mid-span; W at fore; 0 at aft |
| `side_launch.waterContactVelocityMPerS` | `unit-tested` | sqrt(2 g H); sqrt(H) scaling |
| `side_launch.maximumHeelAngleRad` | `unit-tested` | v / sqrt(g GM); v-linear; sqrt(GM) inverse |
| `side_launch.heelVerdict` | `unit-tested` | < boundary pass; >= boundary fail |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `34/34 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: rigid-body kinetics only; the kernel does
  not claim accuracy in the high-speed water-impact regime where
  added mass and hydrodynamic drag become dominant. Linear-stiffness
  heel assumption documented as a Type-I caveat in
  `side_launch.maximumHeelAngleRad`.
- Type-II missed risk guard: typed-error rejection for declivity
  > pi/4, mu > 1, zero L / H / GM / displacement / area, degenerate
  cradle span (L_aft >= L_fore), CG outside span.
- Type-III category guard: launch-kinematics kernel only; not a
  cradle-shape contact-mechanics engine; not a trigger / hold-back
  rope analyser; not a transient pitch / heave time-domain solver.

## What is not covered (v0.0.0)

- Hydrodynamic added mass during launch.
- Water-drag / resistance on entering ship.
- Cradle-shape contact mechanics.
- Trigger / hold-back rope.
- Transient pitch / heave time-history.
- Multi-slipway launch.

## Composition

- Input GM, Delta from `yard-stability-zig` and `yard-hydro-zig`.
- Output way-end velocity feeds the basin-entry resistance
  evaluation in `yard-resistance-zig` for safe stopping distance.
- Pivoting check composes with the structural verification of the
  cradle / launch cradle in classification-society rules.
