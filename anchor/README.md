# yard-anchor-zig

Proof level: `unit-tested`

yard-anchor-zig is a Zig 0.16 anchor holding-power and scope-geometry
kernel. Two modules: `holding` evaluates the IACS A1 Stevin-family
holding-power regression `H = K W^0.92` with K = 1.0 / 1.3 / 1.7 for
standard / HHP / SHHP anchors, plus the chain-friction contribution
`mu w L_floor`; `scope` evaluates the recommended cable-length /
water-depth ratio for adequate anchor performance.

## What it does

### Holding power

- `holding.AnchorType` enum with `kFactor()` returning 1.0, 1.3, 1.7
  for Standard, HHP, SHHP respectively.
- `holding.anchorHoldingKN(W, atype)` returns `K W^0.92`.
- `holding.chainSeabedHoldingKN(mu, w, L)` returns `mu w L`.
- `holding.totalHoldingKN(...)` sums anchor + chain contributions.

### Scope

- `scope.recommended_scope_moderate = 7.0` (7:1 cable / depth).
- `scope.recommended_scope_storm = 10.0`.
- `scope.minimumCableLengthM(depth, ratio)` returns `depth * ratio`.
- `scope.scopeRatio(L, depth)` returns the actual ratio.
- `scope.scopeVerdict(s)` returns acceptable / insufficient.

## What it is not (v0.0.0)

- No seabed-type-specific holding-power adjustment beyond mu (sand /
  mud / rock distinctions).
- No anchor-drag / drift-while-holding model (anchor assumed embedded
  + horizontal shank).
- No dynamic / cyclic load amplification.
- No catenary mooring-cable shape solver (compose with
  `yard-mooring-zig`).
- No anchor-handling tug winch / windlass sizing.
- No type-specific anchor catalogue (caller passes weight).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 19/19 tests passed`.

## Public API

```zig
const yard = @import("yard_anchor");

const H_total = try yard.holding.totalHoldingKN(
    /* W_anchor_kn */ 100.0,
    .HHP,
    /* mu */ 1.0,
    /* w_chain_kn_per_m */ 1.0,
    /* L_floor_m */ 50.0);

const L_req = try yard.scope.minimumCableLengthM(
    30.0, yard.scope.recommended_scope_moderate);
```

## Validation

- Anchor holding at W = 100 kN, Standard reproduces `100^0.92`
  closed form to 1e-9.
- HHP holding = 1.3 x Standard; SHHP = 1.7 x Standard.
- Doubling W scales holding by `2^0.92 ~ 1.893` (sub-linear).
- Chain seabed holding at mu = 1, w = 1 kN/m, L = 50 m equals 50 kN.
- Chain holding scales linearly in mu, w, and L.
- Total holding sums the two contributions.
- Minimum cable at 30 m depth and 7:1 scope equals 210 m.
- Minimum cable at 30 m depth and 10:1 storm scope equals 300 m.
- Scope ratio L / h closed form.
- Verdict acceptable at scope >= 5; insufficient below.
- Typed-error rejection for zero anchor weight, zero friction
  coefficient, zero L_floor, zero depth, scope < 3.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- IACS Unified Requirement A1. *Equipment*.
- Vryhof Anchor Manual. *Stevin / Stevpris HHP / SHHP catalogue*.
- Bowditch, N. (2017). *The American Practical Navigator*.
  NIMA Pub. No. 9. Chapter 7 (Anchoring).
- API Recommended Practice 2SK. *Design and Analysis of
  Stationkeeping Systems for Floating Structures*.

## License

AGPL-3.0-or-later.
