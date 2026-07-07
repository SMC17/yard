# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `magnus.rpmToRps`, `spinRatio`.
- `magnus.C_L_max = 12.0` saturation constant.
- `magnus.liftCoefficientFromSpinRatio` 0.7 SR with saturation.
- `magnus.dragCoefficientFromSpinRatio` 0.5 + 0.2 SR^2/(1 + 0.2
  SR^2).
- `magnus.liftToDragRatio`.
- `rotor.projectedAreaM2`, `liftN`, `dragN`.
- `rotor.decomposeBodyForce` body-frame X / Y decomposition.
- `drive.C_f_default = 0.008` skin friction.
- `drive.frictionTorqueNm`, `drivePowerW`,
  `netPropulsivePowerW`.
- 35-test unit suite including RPM conversion, spin ratio, C_L
  saturation, C_D asymptote, L/D monotonicity, V^2 lift/drag
  scaling, body-frame decomposition, friction torque closed form,
  drive power omega scaling, and negative net propulsive power
  case.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

Magnus C_L and C_D envelopes flagged `claimed`; supplier-specific
rotor curves deferred.
