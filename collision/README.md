# yard-collision-zig

Proof level: `unit-tested`

yard-collision-zig is a Zig 0.16 ship-collision kernel implementing
the Minorsky 1959 right-angle ship-ship collision energy regression
together with added-mass-corrected kinetic energy for the perfectly
plastic two-body impact closed form.

## What it does

- `minorsky.resistanceFactorM3(thicknesses, areas)` returns the
  Minorsky volumetric damage proxy `R_T = sum t_i A_i` [m^3].
- `minorsky.absorbedEnergyMJ(R_T)` returns `47.1 R_T + 32.7` [MJ].
- `kinetic.mu_minorsky_struck_lateral = 1.4` and
  `kinetic.mu_minorsky_striking_longitudinal = 1.0` added-mass
  factors.
- `kinetic.effectiveMassKg(m, mu)` returns `(1 + mu) m`.
- `kinetic.kineticEnergyJ(m, V)` returns `0.5 m V^2`.
- `kinetic.kineticEnergyWithAddedMassJ(m, mu, V)` composes the above.
- `kinetic.rightAngleAbsorbedEnergyJ(m_a, mu_a, V_a, m_b, mu_b)`
  returns the structurally absorbed energy of a perfectly plastic
  right-angle two-ship collision with a struck ship at rest.

## What it is not (v0.0.0)

- No Pedersen-Zhang grounding / raking damage model.
- No super-element finite-element collision-deformation solver.
- No tank-rupture / spill-volume estimator.
- No probabilistic collision-frequency / IMO HAZID gate.
- No oblique-angle collision (cosine-law decomposition deferred).
- No multi-compartment damage-stability follow-on (compose with
  `yard-stability-zig`).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 20/20 tests passed`.

## Public API

```zig
const yard = @import("yard_collision");

const t = [_]f64{ 0.020, 0.015, 0.010 };
const A = [_]f64{ 5.0, 8.0, 3.0 };
const R_T = try yard.minorsky.resistanceFactorM3(&t, &A);
const E_str = try yard.minorsky.absorbedEnergyMJ(R_T);

const E_av = try yard.kinetic.rightAngleAbsorbedEnergyJ(
    1.0e7, yard.kinetic.mu_minorsky_striking_longitudinal,
    8.0,
    2.0e7, yard.kinetic.mu_minorsky_struck_lateral);
```

## Validation

- Single-plate R_T = t A and multi-plate sum closed form.
- E_abs at R_T = 0 equals the intercept 32.7 MJ.
- E_abs scales with slope 47.1 MJ / m^3.
- E_abs at R_T = 10 m^3 equals 503.7 MJ.
- Effective mass `(1 + mu) m` at mu = 0 returns the displacement;
  at mu = 1.4 returns 2.4 m.
- Right-angle absorbed energy:
  - Equal-mass zero-mu pair gives `0.5 E_k_a` (half the striking
    ship's kinetic energy).
  - Striking >> struck dwarfs limit gives `0.5 (1 + mu_b) m_b V^2`.
  - Struck >> striking limit gives `0.5 m_a V^2`.
- Typed-error rejection for unequal lengths, non-positive thickness,
  non-positive mass, negative velocity, negative mu.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Minorsky, V. U. (1959). *An Analysis of Ship Collisions with
  Reference to Protection of Nuclear Power Plants*. J. Ship Research.
- Pedersen, P. T., Zhang, S. (1998). *On Impact Mechanics in Ship
  Collisions*. Marine Structures.
- Paik, J. K., Thayamballi, A. K. (2007). *Ship-Shaped Offshore
  Installations*. Cambridge.

## License

AGPL-3.0-or-later.
