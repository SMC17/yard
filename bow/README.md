# yard-bow-zig

Proof level: `unit-tested`

yard-bow-zig is a Zig 0.16 bulbous-bow kernel implementing the
Holtrop-Mennen 1984 + Holtrop 1988 bulb-and-bow-form regression
chain. Three modules: `holtrop` for the c_2 / c_3 / c_4 / c_7
coefficients; `area` for ellipse-approx A_BT and immersion factor
P_B and bulb-tip Froude number Fn_i; `resistance` for the additive
wave-resistance term R_B.

## What it does

### Coefficient regression

- `holtrop.c3Coefficient(A_BT, B, T, T_F, h_B)` returns
  `0.56 A_BT^1.5 / (B T (0.31 sqrt(A_BT) + T_F - h_B))`.
- `holtrop.c2Coefficient(c_3)` returns `exp(-1.89 sqrt(c_3))`.
- `holtrop.BowShape` enum and `c4Coefficient(shape)` returning the
  Holtrop 1988 Table II bow-form-factor values
  (-1.0 / -0.5 / 0.0 / 0.5 / 1.0).
- `holtrop.c7Coefficient(B, L)` returns the breadth-to-length-ratio
  branch (`0.229577 (B/L)^(1/3)` / `B/L` / `0.5 - 0.0625 L/B`).

### Bulb geometry

- `area.ellipseAreaM2(D_h, D_v)` ellipse-approximation A_BT.
- `area.immersionFactorPB(A_BT, T_F, h_B)` returns
  `0.56 sqrt(A_BT) / (T_F - 1.5 h_B)`.
- `area.bulbFroudeNumber(V, A_BT, T_F, h_B, g)` returns
  `V / sqrt(g (T_F - h_B - 0.25 sqrt(A_BT)) + 0.15 V^2)`.

### Resistance term

- `resistance.bulbResistanceN(P_B, Fn_i, A_BT, rho, g)` returns
  `0.11 exp(-3 / P_B^2) Fn_i^3 A_BT^1.5 rho g / (1 + Fn_i^2)`.
- `resistance.bulbResistanceFromGeometry(...)` one-step composer.
- `resistance.bulbResistanceRatio(R_B, R_W)` ratio against the
  reference wave resistance.

## What it is not (v0.0.0)

- No CFD-derived bulb-shape optimisation.
- No off-design (ballast / heavy) condition correction.
- No transverse-bow-thruster opening drag correction.
- No spray / breaking-bow-wave model.
- No CAD-mesh A_BT extraction.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 32/32 tests passed`.

## Public API

```zig
const yard = @import("yard_bow");

const A_BT = try yard.area.ellipseAreaM2(2.0, 1.6);
const P_B = try yard.area.immersionFactorPB(A_BT, 15.0, 5.0);
const Fn_i = try yard.area.bulbFroudeNumber(8.0, A_BT, 15.0, 5.0, 9.81);
const c3 = try yard.holtrop.c3Coefficient(A_BT, 32.0, 11.0, 15.0, 5.0);
const c2 = yard.holtrop.c2Coefficient(c3);
const c4 = yard.holtrop.c4Coefficient(.U_shaped);
const c7 = try yard.holtrop.c7Coefficient(32.0, 220.0);
const R_B = try yard.resistance.bulbResistanceFromGeometry(
    A_BT, 15.0, 5.0, 8.0, 1025.0, 9.81);
```

## Validation

- c_3 closed-form match at A_BT = 2.56, B = 20, T = 8, T_F = 8,
  h_B = 4.
- c_3 increases with A_BT^1.5.
- c_2 at zero bulb equals 1.
- c_2 closed form at c_3 = 0.04.
- c_4 catalogue values across all five bow shapes.
- c_7 three-branch coverage (narrow / typical / wide).
- Ellipse-area D_h = D_v = 2 gives pi.
- P_B at A_BT = 2.56, T_F = 8, h_B = 4 equals 0.448.
- P_B increases when the bulb is deeper.
- P_B rejects degenerate geometry (T_F <= 1.5 h_B).
- Fn_i scales monotonically with V.
- R_B Aframax-class worked example yields finite non-negative value.
- R_B scales with A_BT^1.5 and rho g, and with Fn_i^3 / (1 + Fn_i^2).
- R_B decay at P_B = 1 equals exp(-3); large P_B saturates to unity.
- Resistance ratio closed form.
- Typed-error rejection for non-positive area / draft / dimensions
  / density / speed and degenerate geometry.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Holtrop, J., Mennen, G. G. J. (1984). *An Approximate Power
  Prediction Method*. International Shipbuilding Progress 31.
- Holtrop, J. (1988). *A Statistical Re-analysis of Resistance and
  Propulsion Data*. International Shipbuilding Progress 35.
- Bertram, V. (2011). *Practical Ship Hydrodynamics*. 2nd ed.,
  Butterworth-Heinemann.
- Kracht, A. M. (1978). *Design of Bulbous Bows*. SNAME Trans. 86.

## License

Apache-2.0.
