# yard-fueltank-zig

Proof level: `unit-tested`

yard-fueltank-zig is a Zig 0.16 MARPOL Annex I Regulation 12A oil-
fuel-tank protection kernel. For ships contracted on or after 1
August 2010 with total oil fuel capacity at or above 600 m^3, the
regulation prescribes a minimum side distance `w` and a minimum
double-bottom height `h` for any individual fuel tank.

## What it does

- `reg_12a.capacity_threshold_m3 = 600` applicability cutoff.
- `reg_12a.requiredSideDistanceM(C)` returns
  `w = 0.4 + 2.4 C / 20 000` clamped to `[1.0, 2.0]` m, or zero
  below the 600 m^3 threshold.
- `reg_12a.requiredDoubleBottomHeightM(C, B)` returns
  `h = clamp(B/20, 2.0, 2.0)` (i.e. minimum 2.0 m), or zero below
  the threshold.
- `reg_12a.complianceVerdict(actual_side, actual_bottom, req_side,
  req_bottom)` pass / fail verdict.

## What it is not (v0.0.0)

- No protective-location alternative-method Regulation 12A.10 (the
  oil-outflow-performance alternative).
- No double-side-skin tanker SBT cross-walk to Regulation 19.
- No fuel-oil tank arrangement for IBC / IGC ships.
- No general-arrangement plan ingestion (caller supplies actual
  distances).
- No tank capacity calculation from tank geometry (compose with
  `yard-hydro-zig` volume integrators).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 15/15 tests passed`.

## Public API

```zig
const yard = @import("yard_fueltank");

const w_req = try yard.reg_12a.requiredSideDistanceM(5000.0);
const h_req = try yard.reg_12a.requiredDoubleBottomHeightM(5000.0, 30.0);
const v = try yard.reg_12a.complianceVerdict(
    1.8, 2.1, w_req, h_req);
```

## Validation

- Below 600 m^3 threshold returns zero requirement.
- Side distance at C = 1000 m^3 yields the lower-clamp value 1.0 m.
- Side distance at C = 10 000 m^3 yields 0.4 + 1.2 = 1.6 m.
- Side distance at C = 13 333 m^3 reaches the upper-clamp 2.0 m.
- Side distance at C = 50 000 m^3 clamps at 2.0 m.
- Double-bottom height at B = 30 m gives B/20 = 1.5 m -> clamped 2.0.
- Double-bottom height at B = 50 m gives B/20 = 2.5 m -> clamped 2.0.
- Compliance verdict pass at actual >= required.
- Compliance verdict fail when either side or bottom < required.
- Typed-error rejection for zero capacity, zero breadth, negative
  actual distance.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- IMO MARPOL Annex I Regulation 12A. *Oil Fuel Tank Protection*.
- IMO Resolution MEPC.141(54). *Amendments to MARPOL Annex I*.
- DNV-RU-SHIP Pt. 5 Ch. 8. *Tanker chemical*.
- IACS Common Structural Rules Section 2 *General Arrangement
  Design*.

## License

AGPL-3.0-or-later.
