# yard-roro-zig

Proof level: `unit-tested`

yard-roro-zig is a Zig 0.16 RoRo / ferry vehicle-deck loading kernel.
Apparent weight under combined vertical acceleration; lateral lashing
force under combined roll angle and lateral acceleration; apparent-
gravity tilt; tipping-angle verdict against the wheel-base geometry.

## What it does

- `deck_load.apparentWeightN(m, g, a_v)` returns `m (g + a_v)`.
- `deck_load.lateralLashingForceN(m, g, a_h, phi)` returns
  `m (a_h + g sin phi)`.
- `deck_load.apparentGravityTiltRad(g, a_v, a_h, phi)` returns the
  tilt of the apparent-gravity vector.
- `deck_load.tippingAngleRad(b, h_cg)` returns
  `atan(b / (2 h_cg))`.
- `deck_load.tippingVerdict(alpha_g, alpha_tipping)` pass / fail.

## What it is not (v0.0.0)

- No stochastic short-term seakeeping spectrum convolution (caller
  composes with `yard-rao-spectrum-zig`).
- No tyre-friction / coefficient-of-friction lateral-slip threshold
  (compose externally).
- No multi-axle / articulated-trailer load distribution.
- No green-water flooding on the deck.
- No fire-class deck-arrangement compliance.
- No IMO Resolution A.581 stowage-and-securing of cargo ships
  ledger.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 16/16 tests passed`.

## Public API

```zig
const yard = @import("yard_roro");

const W = try yard.deck_load.apparentWeightN(20_000.0, 9.81, 5.0);
const F_h = try yard.deck_load.lateralLashingForceN(
    20_000.0, 9.81, 2.0, std.math.pi / 6.0);
const alpha_g = try yard.deck_load.apparentGravityTiltRad(
    9.81, 5.0, 2.0, std.math.pi / 6.0);
const tipping = try yard.deck_load.tippingAngleRad(2.5, 1.8);
const v = yard.deck_load.tippingVerdict(alpha_g, tipping);
```

## Validation

- Apparent weight at rest equals `m g`.
- Apparent weight at `a_v = 5 m/s^2` increases by `m a_v`.
- Apparent weight at free-fall is zero.
- Lateral force at `phi = 0, a_h = 0` is zero.
- Lateral force at 30 deg roll, `a_h = 0` is `m g / 2`.
- Lateral force scales linearly with mass.
- Tipping angle for `b = 2`, `h_cg = 1` is pi/4 (45 deg).
- Tipping angle for narrow tall vehicle is small (atan(0.1)).
- Tipping verdict pass at alpha_g < tipping; fail at >=.
- Apparent-gravity tilt at zero acceleration and `phi = 30 deg`
  equals 30 deg.
- Typed-error rejection for zero mass, roll angle outside
  `[-pi/2, pi/2]`.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- IMO Resolution A.581(14). *Guidelines for Securing Arrangements
  for the Transport of Road Vehicles on Ro-Ro Ships*.
- IMO Code of Safe Practice for Cargo Stowage and Securing
  (CSS Code).
- DNV-RP-G105. *Cargo Securing Standards*.
- Bhattacharyya, R. (1978). *Dynamics of Marine Vehicles*. Wiley.

## License

Apache-2.0.
