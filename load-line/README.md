# yard-load-line-zig

Proof level: `unit-tested`

yard-load-line-zig is a Zig 0.16 freeboard-assignment kernel
implementing the International Convention on Load Lines 1966 (1988
Protocol). Tabular summer freeboard for Type A and Type B ships in
the length range 24 m to 365 m with corrections for block coefficient,
depth, and superstructure length.

## What it does

- `freeboard.ShipType` enum (`.A` and `.B`).
- `freeboard.tabularFreeboardMm(ship_type, L_m)` linear-interpolated
  tabular summer freeboard at the eight-point grid published in ICLL
  Annex I Reg. 28.
- `freeboard.blockCoefficientCorrection(C_B)` Reg. 30 multiplier
  `(C_B + 0.68) / 1.36` for `C_B > 0.68`, else 1.0.
- `freeboard.depthCorrectionMm(L, D)` Reg. 31 additive term
  `(D - L/15) * R` with R = L/0.48 for L >= 120 m, else 250.
- `freeboard.superstructureDeductionMm(ship_type, E/L, L)` Reg. 37
  effective-superstructure deduction with the linear E/L percentage
  approximation and the Type-A / Type-B ceiling at L >= 122 m.
- `freeboard.summerFreeboardMm(ship_type, L, D, C_B, E/L)` composer:
  `F = F_tab * k_CB + dF_depth - dF_super`.

## What it is not (v0.0.0)

- No tropical, winter, winter-North-Atlantic zone-mark conversion.
- No sheer-correction (Reg. 38).
- No bow-height check (Reg. 39).
- No reserve-buoyancy check / freeboard deck cross-curve.
- No timber load-line marks.
- No structural watertight-integrity verification.
- One-metre tabular granularity is approximated by linear
  interpolation of the eight-point grid; ingest the official ICLL
  table when one-millimetre precision is required.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 15/15 tests passed`.

## Public API

```zig
const yard = @import("yard_load_line");

const F_summer = try yard.freeboard.summerFreeboardMm(
    .B,    // Type B
    200.0, // L
    15.0,  // D
    0.75,  // C_B
    0.10,  // E/L
);
```

## Validation

- Tabular endpoints L = 24, 365 m match the published ICLL Annex I
  values exactly (Type A: 200 mm / 4444 mm; Type B: 200 mm / 5303 mm).
- Type B exceeds Type A above the small-vessel regime.
- Linear-interpolation midpoint at L = 125 m for Type A reproduces
  the arithmetic mean of the L = 100 m and L = 150 m endpoints.
- Block-coefficient correction at C_B = 0.68 returns unity; at
  C_B = 0.75 returns (0.75 + 0.68) / 1.36.
- Depth correction zero at D = L/15; below L = 120 m the constant
  R = 250 branch is exercised.
- Superstructure deduction zero at E/L = 0; at E/L = 1 above
  L = 122 m the deduction equals the 1070 mm ceiling.
- `summerFreeboardMm` reproduces the four-term composition exactly.
- Typed-error rejection for non-positive length / depth, out-of-range
  C_B and E/L, length outside [24, 365] m.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- International Convention on Load Lines 1966 (1988 Protocol).
- IMO Resolution A.319(IX). Recommendation on the inspection of load
  line marks.
- Hughes, O. F., Paik, J. K. (2010). *Ship Structural Analysis and
  Design*. SNAME.

## License

AGPL-3.0-or-later.
