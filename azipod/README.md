# yard-azipod-zig

Proof level: `unit-tested`

yard-azipod-zig is a Zig 0.16 azimuthing-thruster + waterjet kernel.
Two modules: `azipod` resolves an open-water thrust into surge / sway
components at a steering angle and applies a wake-fraction correction
to the effective advance velocity; `waterjet` evaluates the momentum-
conservation net thrust `rho Q (V_j - V_in)`, propulsive efficiency
`2 V_in / (V_j + V_in)`, and ideal jet power.

## What it does

### azipod

- `azipod.resolveSteeringForce(T_OW, theta)` returns
  `(T_x, T_y) = T_OW (cos theta, sin theta)`.
- `azipod.advanceVelocity(V_ship, w_T)` returns `V_a = V_ship (1 - w_T)`.
- `azipod.sideForceRatio(theta)` returns `tan(theta)` in the
  longitudinal-dominated regime |theta| < pi/2.

### waterjet

- `waterjet.netThrustN(rho, Q, V_j, V_in)` momentum thrust.
- `waterjet.propulsiveEfficiency(V_j, V_in)` returns
  `2 V_in / (V_j + V_in)`.
- `waterjet.idealJetPowerW(T, V_j, V_in)` returns
  `T (V_j + V_in) / 2`.

## What it is not (v0.0.0)

- No off-design pod thrust-degradation curve (compose with the
  manufacturer's K_T-J map outside the kernel).
- No fish-tail / cross-flow rudder force on the pod strut.
- No waterjet inlet-loss / cavitation model.
- No reverse-thrust bucket geometry.
- No control-allocation optimisation for multi-pod DP vessels.
- No pod / propeller interaction with hull boundary layer.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 20/20 tests passed`.

## Public API

```zig
const yard = @import("yard_azipod");

// Resolve a 100 kN open-water thrust into a 30-degree steering setting.
const c = try yard.azipod.resolveSteeringForce(100_000.0, std.math.pi / 6.0);
// c.Tx_n, c.Ty_n

// Effective advance velocity at V_ship = 15 m/s with w_T = 0.18.
const V_a = try yard.azipod.advanceVelocity(15.0, 0.18);

// Waterjet at rho = 1025, Q = 5 m^3/s, V_j = 30 m/s, V_in = 10 m/s.
const T = try yard.waterjet.netThrustN(1025.0, 5.0, 30.0, 10.0);
const eta = try yard.waterjet.propulsiveEfficiency(30.0, 10.0);
const P = try yard.waterjet.idealJetPowerW(T, 30.0, 10.0);
```

## Validation

- Pure surge at theta = 0; pure sway at theta = pi/2; reverse surge
  at theta = pi.
- Magnitude preserved across the steering rotation.
- Advance velocity at w = 0.2 reduces V_ship by 20 %.
- Side-force ratio tan(0) = 0; tan(pi/4) = 1.0.
- Stationary boat waterjet thrust: `rho Q V_j` closed form
  (153 750 N at 1025 / 5 / 30).
- Zero net thrust at V_j = V_in.
- Linear scaling with rho.
- Propulsive efficiency 2/3 at V_j = 2 V_in; 1.0 at V_j = V_in;
  below 1 for V_j > V_in.
- Ideal jet power T (V_j + V_in) / 2 closed form.
- Typed-error rejection for negative thrust, angle out of range,
  wake fraction >= 1, V_j < V_in, negative density.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Carlton, J. (2018). *Marine Propellers and Propulsion*. 4th ed.,
  Butterworth-Heinemann.
- Allison, J. L. (1993). *Marine Waterjet Propulsion*. SNAME Trans.
- ABB. *Azipod Family of Products*. Manufacturer literature.
- Kuiper, G. (1992). *The Wageningen Propeller Series*. MARIN.

## License

AGPL-3.0-or-later.
