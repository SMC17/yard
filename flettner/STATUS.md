# Status

yard-flettner-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `magnus.rpmToRps` | `unit-tested` | 60 rpm = 2 pi rad/s |
| `magnus.spinRatio` | `unit-tested` | omega R / V closed form |
| `magnus.liftCoefficientFromSpinRatio` | `claimed` | 0.7 SR linear with C_L_max = 12 saturation per Thom 1934 envelope; per-rotor calibration deferred |
| `magnus.dragCoefficientFromSpinRatio` | `claimed` | 0.5 + 0.2 SR^2/(1 + 0.2 SR^2) envelope; stationary-cylinder limit 0.5; asymptote 1.5 verified |
| `magnus.liftToDragRatio` | `unit-tested` | zero at SR=0; monotone growth across operational range |
| `rotor.projectedAreaM2` | `unit-tested` | D h closed form |
| `rotor.liftN`, `dragN` | `unit-tested` | 0.5 rho V^2 D h C closed form; V^2 / rho / area scaling |
| `rotor.decomposeBodyForce` | `unit-tested` | beam-wind pure surge; head-wind pure sway; magnitude preserved |
| `drive.frictionTorqueNm` | `unit-tested` | 0.5 rho V^2 pi D h R C_f closed form; C_f and V^2 scaling |
| `drive.drivePowerW` | `unit-tested` | T omega closed form; omega scaling |
| `drive.netPropulsivePowerW` | `unit-tested` | thrust V - P_drive; negative when drive dominates |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `35/35 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: Magnus C_L and C_D envelopes are
  representative Thom 1934 / Reid 1924 fits; the kernel does not
  claim manufacturer-specific accuracy. C_L and C_D both flagged
  `claimed`; per-rotor calibration is deferred.
- Type-II missed risk guard: typed-error rejection for non-positive
  density / dimension / speed / RPM, negative SR / C_f, theta
  outside [0, 2 pi].
- Type-III category guard: rotor aerodynamics + drive-power
  kernel only; not a structural / fatigue verifier; not a
  multi-rotor control allocator (compose with `yard-dynpos-zig`);
  not a transient spin-up profiler; not a noise / shadow-effect
  model.

## What is not covered (v0.0.0)

- Manufacturer-calibrated C_L(SR) curves.
- End-plate / hubcap geometry effects.
- Transient spin-up power.
- Multi-rotor allocation.
- Rotor-shaft structural verification.
- Noise / shadow effects on bridge.

## Composition

- Input apparent-wind `V` and `theta` from `yard-windaero-zig` or a
  meteorological dataset.
- Output `body.X_n` couples to the propulsion balance: net
  contribution = thrust_x * V_ship - P_drive.
- `decomposeBodyForce` reuses the same body-frame surge/sway
  convention as `yard-dynpos-zig` and `yard-fossen-6dof-zig`.
