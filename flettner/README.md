# yard-flettner-zig

Proof level: `unit-tested`

yard-flettner-zig is a Zig 0.16 Magnus-effect rotor (Flettner)
wind-propulsion kernel. Three modules: `magnus` for the spin ratio
and the lift / drag coefficient envelopes; `rotor` for the
dimensional force and body-frame decomposition; `drive` for the
electric drive power required to maintain rotor RPM against air-
friction torque.

## What it does

### Magnus envelope

- `magnus.rpmToRps(rpm)` converts RPM to angular velocity.
- `magnus.spinRatio(omega, R, V)` returns `omega R / V`.
- `magnus.C_L_max = 12.0` operational saturation cap.
- `magnus.liftCoefficientFromSpinRatio(SR)` returns
  `min(0.7 SR, C_L_max)`.
- `magnus.dragCoefficientFromSpinRatio(SR)` returns
  `0.5 + 0.2 SR^2 / (1 + 0.2 SR^2)`.
- `magnus.liftToDragRatio(SR)` returns `C_L / C_D`.

### Rotor dimensional force

- `rotor.projectedAreaM2(D, h)` returns the rotor face area.
- `rotor.liftN(rho, V, D, h, C_L)` and `rotor.dragN(...)` evaluate
  `0.5 rho V^2 (D h) C`.
- `rotor.decomposeBodyForce(L, D, theta)` decomposes lift and drag
  into surge (X) and sway (Y) at apparent-wind angle `theta`.

### Electric drive

- `drive.C_f_default = 0.008` skin-friction coefficient.
- `drive.frictionTorqueNm(rho, V, D, h, R, C_f)` returns
  `0.5 rho V^2 pi D h R C_f`.
- `drive.drivePowerW(T_friction, omega)` returns `T omega`.
- `drive.netPropulsivePowerW(thrust_x, V_ship, P_drive)` returns
  `thrust * V - P_drive`.

## What it is not (v0.0.0)

- No experimentally-calibrated C_L(SR) for a specific rotor
  manufacturer (the kernel uses a generic Thom 1934 envelope).
- No end-plate / hubcap / Magnus-augmentation geometry.
- No transient spin-up power profile.
- No control-allocation logic for multi-rotor configurations.
- No structural / fatigue verification of the rotor shaft.
- No noise / shadow-effect on ship bridge.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 35/35 tests passed`.

## Public API

```zig
const yard = @import("yard_flettner");

const omega = try yard.magnus.rpmToRps(150.0);
const SR = try yard.magnus.spinRatio(omega, 2.0, 12.0);
const C_L = try yard.magnus.liftCoefficientFromSpinRatio(SR);
const C_D = try yard.magnus.dragCoefficientFromSpinRatio(SR);
const L = try yard.rotor.liftN(1.225, 12.0, 4.0, 24.0, C_L);
const D = try yard.rotor.dragN(1.225, 12.0, 4.0, 24.0, C_D);
const body = try yard.rotor.decomposeBodyForce(L, D, std.math.pi / 3.0);

const T_f = try yard.drive.frictionTorqueNm(
    1.225, 12.0, 4.0, 24.0, 2.0, yard.drive.C_f_default);
const P_drive = try yard.drive.drivePowerW(T_f, omega);
const P_net = yard.drive.netPropulsivePowerW(body.X_n, 8.0, P_drive);
```

## Validation

- RPM-to-RPS conversion: 60 rpm = 2 pi rad/s.
- Spin ratio closed form.
- C_L linear in SR up to C_L_max = 12.0; saturates above.
- C_D at SR = 0 equals 0.5; asymptotes to 1.5; monotone in SR.
- L/D zero at SR = 0; monotone growth across the operational range
  before C_L saturation.
- Projected area `D h`.
- Lift / drag forces with V^2, rho, and area linear scalings.
- Body-frame decomposition: pure surge at beam wind; pure sway at
  head wind (lift perpendicular to apparent wind).
- Magnitude preservation across the lift / drag decomposition.
- Friction torque closed-form match; C_f and V^2 scaling.
- Drive power omega scaling; 10 kW worked example.
- Net propulsive power can go negative when drive exceeds thrust
  contribution.
- Typed-error rejection for non-positive density, dimension, speed,
  RPM, negative SR / C_f, theta outside [0, 2 pi].

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Flettner, A. (1925). *The Flettner Rotor Ship*. Engineering 19.
- Thom, A. (1934). *Effects of Discs on the Air Forces on a Rotating
  Cylinder*. ARC R&M 1623.
- Reid, E. G. (1924). *Tests of Rotating Cylinders*. NACA TN 209.
- Bilgen, E., Boulos, R. (1973). *Functional Dependence of Torque
  Coefficient of Coaxial Cylinders on Gap Width and Reynolds
  Number*. Journal of Fluids Engineering 95.
- Traut, M., Gilbert, P., Walsh, C., Bows, A., Filippone, A.,
  Stansby, P., Wood, R. (2014). *Propulsive power contribution of a
  kite and a Flettner rotor on selected shipping routes*. Applied
  Energy 113.

## License

Apache-2.0.
