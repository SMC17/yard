# yard-ittc78-zig

Proof level: `unit-tested`

yard-ittc78-zig is a Zig 0.16 implementation of the ITTC-78 Performance
Prediction Method (11-step powering extrapolation) as a single scalar-
in, scalar-out function.

## What it does

`chain.extrapolate(model, ship, factors, propeller)` runs the 11-step
ITTC-78 chain:

1. Reynolds at model and ship.
2. C_F at both scales via ITTC-57.
3. Form factor (1+k) caller-supplied.
4. C_T_model caller-supplied from towing-tank.
5. Wave-pattern residual C_R = C_T_model - (1+k) C_F_model.
6. C_R copies to ship under Froude scaling.
7. C_T_ship = (1+k) C_F_ship + C_R + C_A + C_AA, with C_A from the
   model-ship correlation allowance formula and C_AA from the
   informative air-drag convention.
8. R_T_ship = 0.5 rho V^2 S C_T; P_E = R_T V.
9. Wake fraction, thrust deduction, eta_R caller-supplied.
10. Propeller K_T, K_Q caller-supplied at the ship operating J.
11. P_D = 2 pi rho_s n_s^3 D^5 K_Q / eta_R; P_S = P_D / eta_S.

## Composition with yard-resistance-zig and yard-propulsion-zig

This library is intentionally standalone. The caller composes upstream:

- From `yard-resistance-zig`: use `holtrop.totalResistance` to get
  C_T at design speed if no tank data is available, or use measured
  tank-test C_T directly. Form factor (1+k) from
  `holtrop.formFactor1984` or from a Prohaska plot.
- From `yard-propulsion-zig`: at the ship operating J, get K_T and
  K_Q from `wageningen.kT` and `wageningen.kQ`.
- From `yard-hydro-zig`: wetted surface S and other principal
  particulars feed the model and ship structs here.

## What it is not (v0.0.0)

- No Prohaska plot fit (caller supplies (1+k)).
- No self-propulsion test parser (caller supplies w, t, eta_R).
- No propeller selection (caller supplies K_T, K_Q at J_s).
- No appendage allowance, no bilge keel.
- No fuel-consumption estimation.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 12/12 tests passed`.

## Bench

```
zig build bench -Doptimize=ReleaseFast
```

## Public API

```zig
const yard = @import("yard_ittc78");

const model = yard.chain.ModelScale{
    .L = 6.0, .S = 6.5, .V = 1.5, .nu = 1.139e-6,
    .C_T = 0.0042, .rho = 1000.0,
};
const ship = yard.chain.ShipScale{
    .L = 150.0, .S = 4000.0, .V = 7.5, .nu = 1.188e-6,
    .rho = 1025.0, .A_T = 500.0,
};
const factors = yard.chain.PropulsionFactors{
    .one_plus_k = 1.15, .w = 0.3, .t = 0.18, .eta_R = 1.0, .eta_S = 0.98,
};
const prop = yard.chain.Propeller{
    .D = 4.5, .n_s = 2.0, .K_T_s = 0.18, .K_Q_s = 0.028,
};

const r = try yard.chain.extrapolate(model, ship, factors, prop);
// r.P_E_ship, r.P_D_ship, r.P_S_ship, r.C_T_ship, r.C_R, r.C_A, r.C_AA,
// r.rn_model, r.rn_ship, r.cf_model, r.cf_ship, r.R_T_ship.
```

## Validation

- Reynolds numbers match `V * L / nu` to f64 round-off.
- C_R = C_T_model - (1+k) C_F_model to f64 round-off.
- P_S = P_D / eta_S to f64 round-off.
- Correlation allowance C_A formula matches the ITTC-78 published form
  (verified at L = 100 m: C_A ~ 0.000479; at L = 1000 m: negative).
- P_E scales as V^3 at constant C_T within 20 percent (C_F drift with
  Reynolds is the residual).

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- ITTC Recommended Procedure 7.5-02-03-01.4 (1978 Performance
  Prediction Method, current revision).
- Bertram, V. (2012), *Practical Ship Hydrodynamics*, 2nd ed., Ch. 2-3.
- Molland, Turnock, Hudson (2017), *Ship Resistance and Propulsion*,
  2nd ed., Ch. 4-5.
- Codex cross-references at
  `~/codex/concepts/ittc-57-and-ittc-78-extrapolation.md` and
  `~/codex/sources/pdfs/ittc/75-02-03-014-performance-powering-prediction.pdf`.

## License

AGPL-3.0-or-later.
