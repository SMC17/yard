# yard-foilcraft-zig

Proof level: `unit-tested`

yard-foilcraft-zig is a Zig 0.16 hydrofoil kernel for foil-borne
craft. Lift, takeoff (foil-borne) speed, cavitation-onset gate, and
lift-to-drag ratio with surface-piercing vs fully-submerged span
efficiency.

## What it does

- `foil.liftN(rho, V, S, C_L)` returns `0.5 rho V^2 S C_L`.
- `foil.takeoffSpeedMPerS(W, rho, S, C_L)` returns
  `sqrt(2 W / (rho S C_L))`.
- `foil.cavitationOnsetSpeedMPerS(p0, pv, rho, |C_p_min|)` returns
  `sqrt((p0 - pv) / (0.5 rho |C_p_min|))`.
- `foil.cavitationVerdict(V, V_cav)` returns sub_cavitating /
  cavitating.
- `foil.e_surface_piercing = 1.0`, `e_fully_submerged_default = 0.85`
  span efficiency constants.
- `foil.liftToDragRatio(C_L, AR, e, C_D0)` returns
  `C_L / (C_D0 + C_L^2 / (pi AR e))`.

## What it is not (v0.0.0)

- No super-cavitating section (Tulin-Burkart) lift curves above
  cavitation onset.
- No multi-foil configuration (single representative foil only).
- No flap / strut deployment kinematics.
- No water-jet propulsion coupling (compose with
  `yard-azipod-zig::waterjet`).
- No transition (take-off) dynamics (caller composes with seakeeping
  externally).
- No body-foil-interaction induced-drag corrections.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 14/14 tests passed`.

## Public API

```zig
const yard = @import("yard_foilcraft");

const L = try yard.foil.liftN(1025.0, 12.0, 2.0, 0.5);
const V_TO = try yard.foil.takeoffSpeedMPerS(50_000.0, 1025.0, 2.0, 0.5);
const V_cav = try yard.foil.cavitationOnsetSpeedMPerS(
    101_325.0, 1325.0, 1025.0, 1.0);
const v = yard.foil.cavitationVerdict(12.0, V_cav);
const ld = try yard.foil.liftToDragRatio(
    0.5, 6.0, yard.foil.e_fully_submerged_default, 0.01);
```

## Validation

- Lift force closed form to 1e-9 at the worked example.
- Lift scales with V^2.
- Takeoff speed scales with sqrt(W) and inversely with sqrt(C_L).
- Cavitation onset at standard conditions matches closed form.
- Verdict sub-cavitating below V_cav; cavitating at and above.
- Surface-piercing foil L/D exceeds fully-submerged at same C_L,
  AR, C_D0.
- Moderate-AR foil L/D in the 15-25 range with C_D0 = 0.01.
- Typed-error rejection for zero density, zero S, p_v >= p_0.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Faltinsen, O. M. (2005). *Hydrodynamics of High-Speed Marine
  Vehicles*. Cambridge.
- Acosta, A. J. (1973). *Hydrofoils and Hydrofoil Craft*. Annual
  Review of Fluid Mechanics 5.
- Buermann, T. M., Leehey, P., Stilwell, J. J. (1953). *An
  Appraisal of Hydrofoil Supported Craft*. SNAME Trans. 61.
- Tulin, M. P., Burkart, M. P. (1955). *Linearized theory for flows
  about lifting foils at zero cavitation number*.

## License

AGPL-3.0-or-later.
