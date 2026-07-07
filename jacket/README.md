# yard-jacket-zig

Proof level: `unit-tested`

yard-jacket-zig is a Zig 0.16 offshore-jacket Morison wave-load kernel.
Two modules: `morison` evaluates the combined drag + inertia force per
unit length on a circular cylindrical member; `airy` provides linear
Airy-wave kinematics (horizontal velocity and acceleration) with a
Newton-iterated solution of the dispersion relation `omega^2 = g k
tanh(k h)`.

## What it does

### Morison

- `morison.forcePerLengthNM(rho, C_D, C_M, D, u, du_dt)` evaluates
  `0.5 rho C_D D u|u| + rho C_M (pi D^2 / 4) du/dt`.
- `morison.forceUniformN(rho, C_D, C_M, D, u, du_dt, L)` integrates
  over a uniform-kinematics segment of length L.
- `morison.dragOnlyNM(rho, C_D, D, u)` large-KC limit.
- `morison.inertiaOnlyNM(rho, C_M, D, du_dt)` small-KC limit.

### Airy linear wave kinematics

- `airy.waveNumberMInv(omega, h, g)` Newton-iterated dispersion
  solver.
- `airy.horizontalVelocityMPerS(H, omega, k, h, z, phi)` returns
  `0.5 H omega cosh(k(h-z))/sinh(k h) cos(phi)`.
- `airy.horizontalAccelerationMPerS2(H, omega, k, h, z, phi)` returns
  the time derivative.

## What it is not (v0.0.0)

- No stretched / nonlinear Stokes wave kinematics (Airy linear only).
- No diffraction / radiation effects (compose with
  `yard-bem-zig` for large-volume bodies).
- No flexible-member dynamic amplification (rigid-cylinder forces
  only).
- No multi-member shadowing / proximity correction.
- No reliability-based design-load partial factors (compose with
  ISO 19902 externally).
- No global jacket FE solver (this is a load-input kernel).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 18/18 tests passed`.

## Public API

```zig
const yard = @import("yard_jacket");

// Linear-wave kinematics at depth z = 10 m below MSL.
const omega: f64 = 0.7;
const h: f64 = 100.0;
const k = try yard.airy.waveNumberMInv(omega, h, 9.81);
const u = try yard.airy.horizontalVelocityMPerS(8.0, omega, k, h, 10.0, 0.0);
const dudt = try yard.airy.horizontalAccelerationMPerS2(8.0, omega, k, h, 10.0, 0.0);

// Morison force per unit length on a D = 1.5 m brace.
const f = try yard.morison.forcePerLengthNM(1025.0, 1.0, 2.0, 1.5, u, dudt);
```

## Validation

- Combined Morison force matches the sum of drag and inertia closed
  form.
- Uniform force `f_per * L`.
- Drag-only limit at `du/dt = 0` reproduces `0.5 rho C_D D u^2`.
- Inertia-only limit at `u = 0` reproduces `rho C_M (pi D^2 / 4)
  du/dt`.
- Drag preserves sign via `u|u|`; inertia scales linearly with
  `du/dt`; drag scales quadratically with `u`; inertia force scales
  with `D^2`.
- Airy dispersion: deep-water limit `k -> omega^2 / g`; shallow-
  water limit `k -> omega / sqrt(g h)`.
- Particle velocity at MSL crest under deep-water condition is
  `H omega / 2`.
- Particle velocity at trough (phi = pi) is the negative of crest.
- Particle acceleration leads velocity by pi/2.
- Velocity decays with depth in deep water.
- Typed-error rejection for zero density, zero coefficient, zero
  length, `z > h`.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Morison, J. R., O'Brien, M. P., Johnson, J. W., Schaaf, S. A.
  (1950). *The Force Exerted by Surface Waves on Piles*.
  Petroleum Transactions AIME 189.
- DNV-RP-C205. *Environmental Conditions and Environmental Loads*.
- ISO 19902. *Petroleum and natural gas industries: Fixed steel
  offshore structures*.
- Sarpkaya, T. (2010). *Wave Forces on Offshore Structures*.
  Cambridge.

## License

AGPL-3.0-or-later.
