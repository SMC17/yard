# Status

yard-hydro-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per `~/CONVENTIONS.md` C2.

## Proof-vocabulary index

Per `~/CONVENTIONS.md` C1, each module is mapped to a proof level and
evidence. Adjacent claims are allowed where both apply.

| Component | Proof level | Evidence |
|---|---|---|
| `simpson.simpson13` | `unit-tested` | Exact reproduction of `int_0^2 x^3 dx = 4` (Simpson 1/3 is exact for polynomials of degree <= 3); even-ordinate-count rejection; non-positive-spacing rejection |
| `simpson.simpson38` | `unit-tested` | Exact reproduction of `int_0^3 x^3 dx = 20.25`; ordinate-count `3k+1` requirement enforced |
| `wigley.Hull` closed form | `unit-tested` | Direct check of `cB = 4/9`, `cM = cP = cW = 2/3`, `KB = 5T/8`, `BM_T = 3B^2/(35T)`, `BM_L = 3L^2/(40T)`; symmetry of waterline ordinates; midship section area `A_M = (2/3) B T` |
| `box_barge.Barge` closed form | `unit-tested` | Direct check vs `V = LBT`, `KB = T/2`, `BM_T = B^2/(12T)`, `BM_L = L^2/(12T)`, all form coefficients unity; cross-check against Biran 2013 Ch.10 worked example KM_T = 1.6389 |
| `integrate.volumeFromAreas` | `unit-tested` | Simpson on Wigley sectional-area ordinates reproduces closed-form volume to f64 round-off; reproduces box-barge `LBT` to f64 round-off |
| `integrate.waterplaneAreaFromHalfBreadths` | `unit-tested` | Simpson on Wigley waterline reproduces closed-form `(2/3) L B` to f64 round-off |
| `integrate.iTFromHalfBreadths` | `unit-tested` | Convergence test verifies O(h^4) ratio between N=20 and N=40 intervals; box-barge case exact to f64 round-off |
| `integrate.lcbFromAreas` | `unit-tested` | Wigley LCB returns exactly zero (within 1e-12) by symmetry |

## Constraint inheritance (C2)

`yard-hydro-zig` is bound by Zig 0.16 (pre-1.0). Until Zig ships 1.0,
no Zig project in the stax substrate can claim v1.0 in semver spirit.

Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `28/28 tests pass`.

Verification command:

```
zig build test --summary all
```

Expected last-line output: `Build Summary: 3/3 steps succeeded; 28/28 tests passed`.

If this drifts, see C5 honesty-correction template.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context. The closest claim is the explicitly
qualified `stable-on-zig-0.16-today`.

## Error taxonomy (C6)

- Type-I overclaim guard: every numerical claim is paired with an
  exact analytical or convergence-rate target. No "fast", "efficient",
  or "competitive" claims without measurement.
- Type-II missed-risk guard: convergence behavior of non-exact
  integrators (I_T on Wigley) is itself a tested property, not
  assumed; the test verifies the expected O(h^4) order rather than
  trusting one h to give "close enough" agreement.
- Type-III category guard: this is a substrate primitive library, not
  a ship-design tool. Ship-design is a category higher; explicit
  out-of-scope note in README guards against the wrong-category claim.

## What is not covered (v0.0.0)

- Bonjean curves (sectional-area-as-function-of-draft tables).
- Damage stability (lost-buoyancy or added-weight methods).
- Free-surface correction.
- GZ curve (small-angle, wall-sided, or pressure-integration).
- IGES or offsets-table parsing.
- Resistance prediction (Holtrop-Mennen).
- Seakeeping (strip theory).
- Hull-girder strength (IACS UR S11).
- Classification compliance (IS Code 2008, MARPOL, SOLAS).

These are downstream of the foundation primitives shipped here.

## Validation against codex substrate

Closed-form derivations and reference values cross-check against the
codex atomic-concept notes:

- `~/codex/concepts/simpsons-rule-for-naval-architecture.md`
- `~/codex/concepts/bonjean-curves.md`
- `~/codex/sources/validation_fixtures.md`
- `~/codex/sources/hulls/wigley/parametric.md`
- `~/codex/sources/hulls/series60/series60_reference_values.md`

Discrepancy between codex and code is resolved per `~/CONVENTIONS.md` C10
(substrate-derived numeric facts override narrative).
