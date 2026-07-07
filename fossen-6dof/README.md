# yard-fossen-6dof-zig

Proof level: `unit-tested`

yard-fossen-6dof-zig is a Zig 0.16 linearized 6-DOF state-space
integrator for marine craft per Fossen (2011) *Handbook of Marine Craft
Hydrodynamics and Motion Control*. RK4 timestep; diagonal constant
mass matrix; linear damping; linearized restoring on heave, roll,
pitch.

## What it does

- `fossen.State` typed (eta, nu) = (NED + Euler, body velocity).
- `fossen.Parameters` typed (M_diag, D_lin, K_z, K_phi, K_theta).
- `fossen.rk4Step(state, params, tau, h)` advances the state by one
  RK4 step.

## What it is not (v0.0.0)

- No nonlinear C(nu) Coriolis/centripetal coupling.
- No nonlinear quadratic damping D(nu).
- No off-diagonal added mass.
- No DP controller.
- No autopilot.
- No environmental wind/wave/current forcing (caller wraps as part of tau).
- No quaternion attitude (Euler angles, valid only for moderate roll
  and pitch).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 11/11 tests passed`.

## Public API

```zig
const yard = @import("yard_fossen_6dof");
const f = yard.fossen;

const p: f.Parameters = .{
    .M_diag = .{ 1.0e6, 1.0e6, 1.0e6, 1.0e7, 1.0e7, 1.0e7 },
    .D_lin = .{ 1.0e4, 1.0e4, 1.0e4, 1.0e5, 1.0e5, 1.0e5 },
    .K_z = 1.0e6, .K_phi = 1.0e7, .K_theta = 1.0e7,
};
var s: f.State = .{ .eta = .{ 0, 0, 0, 0, 0, 0 }, .nu = .{ 0, 0, 0, 0, 0, 0 } };
const tau: [6]f64 = .{ 1.0e4, 0, 0, 0, 0, 0 };
s = try f.rk4Step(s, p, tau, 0.1);
```

## Validation

- Zero state + zero input stays zero to f64 round-off.
- Surge step input drives surge velocity from rest and converges
  toward steady-state `tau / D_lin` within 1 percent over 5000 s.
- Heave restoring brings z back toward zero with damping.
- Linearized M and D produce decoupled channels (surge and sway
  evolve independently in proportion to their forcing).
- Roll oscillation damps over its natural period.
- Impulsive surge response over small h matches `tau * h / M` within
  1e-4 (RK4 linear-damping correction is small at this h).

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Fossen, T. I. (2011), *Handbook of Marine Craft Hydrodynamics and
  Motion Control*, Wiley, Ch. 7-11.
- Codex cross-references at
  `~/codex/concepts/fossen-6dof-maneuvering-model.md`.

## License

Apache-2.0.
