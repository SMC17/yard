# yard-helideck-zig

Proof level: `unit-tested`

yard-helideck-zig is a Zig 0.16 offshore-helideck motion-envelope
kernel covering ICAO Annex 14 / UK CAA CAP 437 / IMO MSC.1/Circ.1378
operating limits for helicopter classes 1, 2, and 3. Pitch / roll /
combined inclination / heave-velocity envelopes plus lateral
acceleration at the deck CG from roll angular acceleration.

## What it does

- `motion.HelideckClass` enum (Class_1, Class_2, Class_3).
- `motion.MotionLimits` typed struct.
- `motion.limitsForClass(cls)` returns the four motion limits per
  class.
- `motion.lateralAccelerationFromRollMPS2(phi_dd, h)` returns the
  lateral acceleration at a deck CG height `h` above the roll axis.
- `motion.inclinationDeg(pitch_deg, roll_deg)` returns
  `sqrt(pitch^2 + roll^2)` (small-angle approximation).
- `motion.envelopeVerdict(cls, pitch, roll, heave_rate)` returns
  pass / fail.

## What it is not (v0.0.0)

- No per-aircraft individual MEL (operator-specific minimum equipment
  list) overrides.
- No probability-of-operation cumulative-distribution lookup.
- No deck-edge airflow / turbulence envelope.
- No engine-fail-on-deck (EOD) net-positive-buoyancy clearance.
- No fire / foam / friction-coefficient verification (helideck
  surface markings).
- No T-D / RIM perimeter geometry check.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 14/14 tests passed`.

## Public API

```zig
const yard = @import("yard_helideck");

const limits = yard.motion.limitsForClass(.Class_1);
const a_y = try yard.motion.lateralAccelerationFromRollMPS2(0.1, 5.0);
const beta = yard.motion.inclinationDeg(1.0, 1.5);
const v = try yard.motion.envelopeVerdict(.Class_1, 1.0, 1.5, 0.5);
```

## Validation

- Class 1 limits exactly 1.5 / 2.5 / 2.0 / 0.9.
- Class 3 envelope strictly larger than Class 1 in every dimension.
- Lateral acceleration `phi_dd * h` closed form.
- Inclination at pitch = 3, roll = 4 equals 5.
- Envelope pass at well-inside-limits motions.
- Envelope fail when roll exceeds class limit; heave-rate exceeds
  limit; combined inclination exceeds limit even when each
  axis-limit individually passes.
- Class 3 admits motions that would fail Class 1.
- Typed-error rejection for negative pitch, zero deck-CG height.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- ICAO Annex 14 Volume II. *Heliports*.
- UK CAA CAP 437. *Standards for Offshore Helicopter Landing Areas*.
- IMO MSC.1/Circ.1378. *Guidelines for the Approval of Alternatives
  and Equivalents as Provided for in Various IMO Instruments*.
- IMO MSC.1/Circ.1054. *Helicopter Landing Areas on Ships*.
- HCA. *Helideck Certification Agency* operating guidance.

## License

AGPL-3.0-or-later.
