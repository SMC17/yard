# yard-icebreaker-zig

Proof level: `unit-tested`

yard-icebreaker-zig is a Zig 0.16 ice-resistance kernel implementing
the Lindqvist 1989 three-component decomposition for ships in level
ice: crushing `R_c`, bending `R_b`, and submersion `R_s`, with a
small speed-dependent correction to the bending term proportional to
the ice-thickness Froude number `V / sqrt(g h)`.

## What it does

- `lindqvist.Geometry` hull-geometry struct (B, T, alpha, phi, psi
  in degrees per the Lindqvist convention).
- `lindqvist.IceProperties` ice-property struct (h, sigma_f, mu,
  rho_w, rho_i).
- `lindqvist.crushingResistanceN` evaluates the compact
  `0.5 sigma_f h^2 tan(alpha)` form.
- `lindqvist.bendingResistanceN` evaluates the Lindqvist 1989
  bending term with the `0.003 sigma_f sqrt(B/h) h^2 *
  (tan(psi) + mu cos(phi)/(cos(psi) sin(alpha)))` formulation.
- `lindqvist.submersionResistanceN` evaluates the buoyancy +
  friction term `(rho_w - rho_i) g h B T *
  (cos(phi)/(cos(psi) sin(alpha)) + mu (sin(phi) +
  cos(phi)/tan(alpha)))`.
- `lindqvist.totalResistance(geom, ice, V)` returns a
  `ResistanceBreakdown` struct with the three components and the
  total, applying the `1 + 1.4 Fn_h` speed-dependent bending
  correction.

## What it is not (v0.0.0)

- No managed-channel / brash-ice regime (caller composes a separate
  reduction factor).
- No icebreaking-power chain (compose with `yard-ittc78-zig` on the
  total).
- No ridge-load model (per IMO Polar Code / IACS PC).
- No transient-load / impact-pressure model.
- No POAC ice-load probabilistic envelope.
- No multi-layer ice (first-year vs multi-year stiffness).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 12/12 tests passed`.

## Public API

```zig
const yard = @import("yard_icebreaker");

const geom = yard.lindqvist.Geometry{
    .B_m = 20.0, .T_m = 7.0,
    .alpha_deg = 30.0, .phi_deg = 40.0, .psi_deg = 30.0,
};
const ice = yard.lindqvist.IceProperties{
    .h_m = 1.0, .sigma_f_pa = 500.0e3, .mu = 0.10,
    .rho_w_kg_per_m3 = 1025.0, .rho_i_kg_per_m3 = 900.0,
};
const r = try yard.lindqvist.totalResistance(geom, ice, 4.0);
// r.R_c_n, r.R_b_n, r.R_s_n, r.R_total_n
```

## Validation

- Crushing reproduces `0.5 sigma_f h^2 tan(alpha)` closed form to 1 N.
- Crushing scales with sigma_f and h^2 (doubling h quadruples R_c).
- Bending positive and order-of-magnitude consistent.
- Submersion positive; scales linearly with `(rho_w - rho_i)`.
- Total at V = 0 equals `R_c + R_b + R_s` without correction.
- Speed-dependent bending correction increases `R_b` at finite V
  while leaving `R_c`, `R_s` unchanged.
- Typed-error rejection for zero ice thickness, negative speed,
  alpha out of (0, 90) deg, and `rho_i >= rho_w`.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Lindqvist, G. (1989). *A Straightforward Method for Calculation
  of Ice Resistance of Ships*. POAC '89.
- Riska, K. (2010). *Design of Ice-Breaking Ships*. Course Notes,
  Aalto University.
- IACS Unified Requirement for Polar Class Ships (URI).
- IMO International Code for Ships Operating in Polar Waters
  (Polar Code).

## License

Apache-2.0.
