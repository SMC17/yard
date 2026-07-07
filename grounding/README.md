# yard-grounding-zig

Proof level: `unit-tested`

yard-grounding-zig is a Zig 0.16 simplified grounding / bottom-raking
kernel per the Pedersen-Zhang 2000 mean-force decomposition. A ship
of mass `m` and approach speed `V` striking a rigid rock of mean
height `h_r` produces a horizontal raking force `F_H` proportional
to `sigma_y t h_r` with a shape factor `C_g`, and the damage length
follows from the energy-force balance `L_damage = E_kin / F_H`.

## What it does

- `pedersen_zhang.kineticEnergyJ(m, mu_x, V)` returns
  `0.5 (1 + mu_x) m V^2` [J] with the longitudinal added-mass
  correction.
- `pedersen_zhang.meanHorizontalForceN(sigma_y, t, h_r, C_g)` returns
  the simplified Pedersen-Zhang horizontal force `sigma_y t h_r C_g`.
- `pedersen_zhang.C_g_smooth_rock = 1.62` shape factor for the
  smooth-rock asperity case.
- `pedersen_zhang.dampageLengthM(E_kin, F_H)` returns the
  energy-balance damage length.
- `pedersen_zhang.GroundingInputs` / `GroundingResult` typed structs.
- `pedersen_zhang.analyseGrounding(inputs)` composer.

## What it is not (v0.0.0)

- No bottom-shape (rock height) probabilistic envelope.
- No conical / parabolic asperity model (only smooth-rock C_g).
- No transient impact-load model.
- No tank-rupture / spill estimator (caller composes externally).
- No double-bottom intact / pierced verdict.
- No coupled stranding-stability follow-on (compose with
  `yard-stability-zig` damage stability).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 12/12 tests passed`.

## Public API

```zig
const yard = @import("yard_grounding");

const in: yard.pedersen_zhang.GroundingInputs = .{
    .m_kg = 10_000_000.0,
    .mu_x = 0.05,
    .V_mps = 6.0,
    .sigma_y_pa = 235e6,
    .plate_thickness_m = 0.020,
    .rock_height_m = 2.0,
    .C_g = yard.pedersen_zhang.C_g_smooth_rock,
};
const r = try yard.pedersen_zhang.analyseGrounding(in);
// r.E_kin_j, r.F_H_n, r.damage_length_m
```

## Validation

- Kinetic energy at 10000 t, mu = 0.05, V = 6 m/s matches
  `0.5 1.05 m V^2 = 189 MJ`.
- Horizontal force at sigma_y = 235 MPa, t = 20 mm, h_r = 2 m,
  C_g = 1.62 matches `15.228 MN` in the [15, 16] MN window.
- Damage length E/F closed form to 1e-12.
- analyseGrounding composes the three steps consistently.
- mu = 0 reduces kinetic energy to `0.5 m V^2`.
- Horizontal force scales linearly in plate thickness and rock
  height.
- Damage length scales with V^2 (quadrupling for doubled speed).
- Typed-error rejection for negative velocity, zero plate
  thickness, zero rock height.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Pedersen, P. T., Zhang, S. (1998). *On Impact Mechanics in Ship
  Collisions*. Marine Structures.
- Pedersen, P. T., Zhang, S. (2000). *Absorbed Energy in Ship
  Collisions and Grounding - Revising Minorsky's Empirical Method*.
  J. Ship Research.
- Wang, G., Spencer, J., Chen, Y. (2002). *Assessment of a Ship's
  Performance in Accidents*. Marine Structures.
- IMO MEPC.122(52). *Explanatory notes on matters related to the
  accidental oil outflow performance under regulation 23 of the
  revised MARPOL Annex I*.

## License

AGPL-3.0-or-later.
