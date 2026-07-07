# Status

yard-stability-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `gz.smallAngleGZ` | `unit-tested` | Zero at zero heel; equals GM at 90 deg |
| `gz.wallSidedGZ` | `unit-tested` | Exceeds small-angle at moderate phi; cross-check against box-barge fixture (~ 0.1134 m at 10 deg with GM=0.6389, BM_T=0.8889); converges to small-angle at tiny phi |
| `gz.rectTankIfs` | `unit-tested` | Exact algebraic check |
| `gz.fsContribution` | `unit-tested` | Match against validation_fixtures Section 2 box-barge (~ 0.183 m) |
| `gz.effectiveGM` | `unit-tested` | Multi-tank linear superposition check |
| `damage.boxBargeOneCompartment` | `unit-tested` | Cross-check against validation_fixtures Section 2 (T_damaged = 1.875 m for 1 of 5 compartments flooded); permeability scaling; explicit rejection of flooding above hull depth and invalid mu |
| `damage.boxBargeIntactIT` | `unit-tested` | Direct algebraic check |
| `is_code.evaluate` | `unit-tested` | Six-criterion pass on a synthetic well-behaved hull; GM_0 fail when below 0.15 m; GZ-at-30-deg via linear interpolation; explicit rejection of non-monotonic or insufficient samples |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `19/19 tests pass`.

```
zig build test --summary all
```

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: GZ-curve area integration in `is_code` is
  trapezoidal; sample density is the caller's responsibility. The
  evaluator does not silently smooth the curve.
- Type-II missed risk guard: explicit error variants for
  non-monotonic samples, insufficient samples, invalid permeability,
  flooding-above-hull-depth.
- Type-III category guard: this is an intact-stability + box-barge
  damage tool, not a probabilistic-damage-stability solver (SOLAS
  II-1 A index) and not a general-hull damage solver. Out of scope.

## What is not covered (v0.0.0)

- General-hull damage (offsets-table-driven lost buoyancy).
- IS Code 2.3 weather criterion.
- SOLAS II-1 Part B-1 probabilistic A-index.
- IMO Grain Code (heeling moment due to grain shift).
- Cross-flooding + progressive flooding.

## Validation against codex substrate

Formulas and reference values traced to
`~/codex/concepts/gz-curve-wall-sided-approximation.md`,
`~/codex/concepts/free-surface-correction.md`,
`~/codex/concepts/lost-buoyancy-damage-stability-method.md`,
`~/codex/sources/validation_fixtures.md`,
`~/codex/sources/standards_machine_readable/imo_is_code_2008_intact_stability.yaml`.
