# yard-deck-zig

Proof level: `unit-tested`

yard-deck-zig is a Zig 0.16 deck-crane kernel covering Safe Working
Load (SWL), outreach load chart interpolation, slewing-centre moment-
limit charts, crane-on-ship tipping check against the static righting
moment, dynamic amplification factor (DAF) per DNV-OS-C201, wave-
driven vertical acceleration on the crane tip, and SWL derating.

## What it does

### Crane SWL + outreach

- `crane.heelingMomentNm(SWL_t, r, g)` returns the slewing-centre
  moment `SWL * g * r * 1000`.
- `crane.swlFromChart(r_arr, swl_arr, r)` piecewise-linear chart
  interpolation with clamping at the endpoints.
- `crane.swlMomentLimit(M_max, r, g)` hyperbolic-tip moment-limit
  chart `SWL = M_max / (g r * 1000)`.

### Tipping check

- `tipping.rightingMomentNm(Delta, GM, phi, g)` returns
  `Delta g GM sin(phi) * 1000`.
- `tipping.equilibriumHeelRad(M_heel, Delta, GM, g)` returns the
  heel angle that balances the heeling moment, or
  `Error.InvalidAngle` for overturning.
- `tipping.tippingVerdict(M_heel, Delta, GM, phi_max, g)` returns
  pass / fail.

### Dynamic load

- `dynamic.dynamicAmplificationFactor(a_v, g)` returns `1 + a_v/g`.
- `dynamic.dynamicLoadN(SWL, a_v, g)` returns `SWL g DAF * 1000`.
- `dynamic.waveDrivenAccelerationMPS2(Hs, T_z)` returns
  `1.2 Hs / T_z^2`.
- `dynamic.deratedSWL(SWL_static, a_v, g)` returns `SWL / DAF`.

## What it is not (v0.0.0)

- No crane structural analysis (boom / pedestal / slewing-ring
  stress).
- No multi-fall block tackle wire-tension analysis.
- No two-block / over-hoist anti-collision logic.
- No load-line / wire-fatigue calculation.
- No knuckle-boom kinematics.
- No personnel-transfer crane envelope (different DAF + safety
  factor).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 35/35 tests passed`.

## Public API

```zig
const yard = @import("yard_deck");

// Load chart interpolation.
const r_arr = [_]f64{ 10.0, 20.0, 30.0 };
const swl_arr = [_]f64{ 100.0, 50.0, 25.0 };
const SWL_at_15 = try yard.crane.swlFromChart(&r_arr, &swl_arr, 15.0);
const M_heel = try yard.crane.heelingMomentNm(SWL_at_15, 15.0, 9.81);

// Tipping check.
const v = try yard.tipping.tippingVerdict(
    M_heel, 25_000.0, 2.0, std.math.pi / 12.0, 9.81);

// Dynamic load.
const a_v = try yard.dynamic.waveDrivenAccelerationMPS2(4.0, 8.0);
const F_dyn = try yard.dynamic.dynamicLoadN(SWL_at_15, a_v, 9.81);
const SWL_derated = try yard.dynamic.deratedSWL(SWL_at_15, a_v, 9.81);
```

## Validation

- Heeling moment at 50 t / 20 m matches closed form.
- Heeling moment scales linearly with SWL and r.
- SWL chart at midpoint between (10, 100) and (20, 50) gives 75.
- SWL chart at exact anchor returns exact SWL.
- SWL chart clamping at both ends.
- Moment-limit chart `SWL r = constant`.
- Righting moment at phi = 0 is zero.
- Righting moment scales with sin(phi).
- Equilibrium heel: at M_heel = 0 is zero; at M_critical equals pi/2;
  above critical returns InvalidAngle.
- Tipping pass at small crane moment; fail at very large moment.
- DAF at a_v = 0 equals 1; at a_v = g equals 2; at -g/2 equals 0.5.
- Dynamic load closed form at 50 t / a_v = 2.
- Wave-driven acceleration scales with `Hs / T_z^2`.
- Derated SWL at a_v = g equals half static.
- Typed-error rejection for non-positive SWL / outreach / GM /
  displacement, chart length errors, invalid heel angle.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- DNV-OS-C201. *Structural Design of Offshore Units (WSD Method)*.
- IACS Rec. 38. *Lifting Appliances on Board Ships*.
- DNV-RP-N103. *Modelling and Analysis of Marine Operations*.
- ISO 19901-6. *Offshore Structures: Marine operations*.
- Lloyd's Register. *Code for Lifting Appliances in a Marine
  Environment*.

## License

AGPL-3.0-or-later.
