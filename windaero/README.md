# yard-windaero-zig

Proof level: `unit-tested`

yard-windaero-zig is a Zig 0.16 ship wind-coefficient kernel inspired
by Blendermann 1996. Single-mode Fourier approximations of `C_X(eps)
~ cos(eps)`, `C_Y(eps) ~ sin(eps)`, and `C_N(eps) ~ sin(2 eps)` with
peak values calibrated per major ship-type category. Dimensional
forces and yaw moment via standard `0.5 rho V^2 A C` form.

## What it does

- `blendermann.rho_air_standard = 1.225 kg/m^3`.
- `blendermann.ShipType` enum (Container, Tanker, Bulk, Passenger,
  Generic) with `peakCoefficients()` returning (C_X_max, C_Y_max,
  C_N_max).
- `blendermann.longitudinalCoefficient(eps, stype)` returns
  `C_X_max cos(eps)`.
- `blendermann.lateralCoefficient(eps, stype)` returns
  `C_Y_max sin(eps)`.
- `blendermann.yawMomentCoefficient(eps, stype)` returns
  `C_N_max sin(2 eps)`.
- `blendermann.longitudinalForceN(rho, V, A_L, eps, stype)`,
  `lateralForceN(rho, V, A_T, eps, stype)`,
  `yawMomentNm(rho, V, A_L, L_OA, eps, stype)`.

## What it is not (v0.0.0)

- No full Blendermann Fourier expansion (the kernel uses single-
  mode shapes; for asymmetric superstructure profiles a multi-mode
  fit is required).
- No height-of-CG-of-windage / heeling moment (caller composes for
  static heel via `yard-stir-zig::dead_ship`).
- No turbulence intensity / atmospheric-boundary-layer gradient.
- No gust-spectrum convolution.
- No fixed-platform (jacket / FPSO) wind coefficient catalogue.
- No anti-rolling / sail-augmentation profiles (compose with
  `yard-keel-zig::appendage` for sail forces).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 13/13 tests passed`.

## Public API

```zig
const yard = @import("yard_windaero");

const X = try yard.blendermann.longitudinalForceN(
    yard.blendermann.rho_air_standard, 20.0, 1000.0, 0.0, .Container);
const Y = try yard.blendermann.lateralForceN(
    yard.blendermann.rho_air_standard, 20.0, 500.0, std.math.pi / 4.0, .Container);
const N = try yard.blendermann.yawMomentNm(
    yard.blendermann.rho_air_standard, 20.0, 1000.0, 200.0,
    std.math.pi / 4.0, .Container);
```

## Validation

- Head wind eps = 0: surge force positive, sway force zero, yaw
  moment zero.
- Beam wind eps = pi/2: surge force zero, sway force positive.
- Yaw moment peaks at eps = pi/4 (`sin(2 eps)` mode).
- Force scales with V^2.
- Container peak (0.55, 0.85, 0.13) matches catalogue.
- Tanker C_Y < Passenger C_Y (smaller superstructure -> lower).
- C_Y sign reverses with apparent-angle sign.
- Stern wind eps = pi gives negative surge force.
- Yaw moment at eps = pi/2 is zero (sin(pi) = 0).
- Typed-error rejection for eps outside [-pi, pi], zero density,
  zero L_OA.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Blendermann, W. (1996). *Wind loading of ships - collected data
  from wind-tunnel tests in uniform flow*. IFS Hamburg Report 574.
- Isherwood, R. M. (1972). *Wind resistance of merchant ships*.
  Trans. RINA 115.
- DNV-RP-C205. *Environmental Conditions and Environmental Loads*.
- OCIMF. *Mooring Equipment Guidelines*.

## License

AGPL-3.0-or-later.
