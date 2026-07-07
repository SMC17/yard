# yard-springing-zig

Proof level: `unit-tested`

yard-springing-zig is a Zig 0.16 hull-girder vibration kernel covering
Schlick's two-node vertical-bending natural frequency and the
free-decay whipping response of an underdamped beam-bending mode.

## What it does

### Hull-girder frequency

- `hull_girder.twoNodeBendingHz(I_v, Delta, L, phi)` returns
  `f_2 = phi sqrt(I_v / (Delta L^3))`.
- `hull_girder.twoNodeBendingRps(f)` returns `2 pi f`.
- `hull_girder.twoNodePeriodSec(f)` returns `1 / f`.
- `hull_girder.phi_schlick_merchant_si = 32 000` calibration
  constant for merchant ships.

### Whipping free decay

- `whipping.dampedAngularFrequencyRps(omega_n, zeta)` returns
  `omega_n sqrt(1 - zeta^2)`.
- `whipping.freeDecayAmplitude(omega_n, zeta, t)` evaluates
  `exp(-zeta omega_n t) cos(omega_d t)`.
- `whipping.logarithmicDecrement(zeta)` returns
  `2 pi zeta / sqrt(1 - zeta^2)`.

## What it is not (v0.0.0)

- No higher-mode (4-node, 6-node) natural-frequency extraction
  (compose with a transfer-matrix Holzer-style chain).
- No fluid added-mass / coupling correction (the Schlick coefficient
  approximates this empirically).
- No springing wave-induced steady-state response (caller composes
  with `yard-rao-spectrum-zig` excitation).
- No slamming pressure-load engine.
- No statistical bending-moment envelope (long-term Hs / Tp gates).
- No fatigue accumulation from whipping (compose with
  `yard-csr-fatigue-zig`).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 18/18 tests passed`.

## Public API

```zig
const yard = @import("yard_springing");

const f_2 = try yard.hull_girder.twoNodeBendingHz(
    200.0, 50_000.0, 200.0, yard.hull_girder.phi_schlick_merchant_si);
const omega_n = yard.hull_girder.twoNodeBendingRps(f_2);

const omega_d = try yard.whipping.dampedAngularFrequencyRps(omega_n, 0.015);
const env = try yard.whipping.freeDecayAmplitude(omega_n, 0.015, 2.0);
const delta = try yard.whipping.logarithmicDecrement(0.015);
```

## Validation

- Schlick formula scales with `sqrt(I)`, `1 / sqrt(Delta)`, and
  `1 / L^(3/2)`.
- Angular frequency 2 pi conversion to 1e-12.
- Period 1 / f closed form.
- Damped frequency at zeta = 0 equals natural; at zeta = 0.1 matches
  `omega_n sqrt(0.99)`.
- Free-decay amplitude at t = 0 equals 1.
- Envelope decays monotonically over multiple half-periods.
- Logarithmic decrement at zeta = 0 is zero; at zeta = 0.1 matches
  `2 pi 0.1 / sqrt(0.99)`.
- Typed-error rejection for zero displacement, zero phi, overdamped
  zeta >= 1, negative time, zero natural frequency.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Schlick, O. (1894). *Die Festigkeit des Schiffskorpers*. ZVDI 38.
- Bishop, R. E. D., Price, W. G. (1979). *Hydroelasticity of Ships*.
  Cambridge.
- Storhaug, G. (2007). *Experimental investigation of wave induced
  vibrations and their effect on the fatigue loading of ships*.
  PhD thesis, NTNU.
- DNV-CG-0153. *Class Guideline for Fatigue Assessment of Ship
  Structures*.

## License

Apache-2.0.
