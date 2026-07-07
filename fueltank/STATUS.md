# Status

yard-fueltank-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `reg_12a.requiredSideDistanceM` | `unit-tested` | below-threshold zero; 1.0 m clamp at low C; 1.6 m at C=10k m^3; 2.0 m clamp at C=13.3k+ |
| `reg_12a.requiredDoubleBottomHeightM` | `unit-tested` | 2.0 m floor and ceiling; both small-B and large-B clamp |
| `reg_12a.complianceVerdict` | `unit-tested` | pass at >= boundary; fail when either dimension below required |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `15/15 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: simplified Reg. 12A side-distance formula
  only. The kernel does not claim to evaluate Reg. 12A.10 oil-
  outflow alternative-method calculation. Caller composes
  externally for the alternative-method submission.
- Type-II missed risk guard: typed-error rejection for zero
  capacity, zero breadth, negative actual distance.
- Type-III category guard: arrangement-distance compliance check
  only; not a general-arrangement plan parser; not an oil-outflow
  probabilistic analyser; not a tank-capacity volume integrator.

## What is not covered (v0.0.0)

- Reg. 12A.10 oil-outflow alternative-method.
- IGC / IBC fuel-oil arrangement.
- General-arrangement plan ingestion.
- Tank-capacity volume from tank geometry.
- Multi-tank pumping / cargo-handling arrangement.

## Composition

- Input `C` couples to `yard-hydro-zig` volume-integrator outputs
  for individual oil-fuel tanks.
- Input `B` is the ship moulded breadth, the same `B` consumed by
  `yard-strength-zig` and `yard-stability-zig`.
- Output verdict feeds the general-arrangement compliance ledger.
