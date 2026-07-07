# Status

yard-anchor-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `holding.AnchorType.kFactor` | `claimed` | K = 1.0 / 1.3 / 1.7 per IACS A1 + Vryhof convention; supplier-specific anchor data may differ |
| `holding.anchorHoldingKN` | `unit-tested` | K W^0.92 closed form; HHP / SHHP scaling exact |
| `holding.chainSeabedHoldingKN` | `unit-tested` | mu w L closed form; linear in all three |
| `holding.totalHoldingKN` | `unit-tested` | sum of contributions |
| `scope.minimumCableLengthM` | `unit-tested` | 210 m at 30 m depth + 7:1 scope; 300 m at 10:1 |
| `scope.scopeRatio` | `unit-tested` | L / h closed form |
| `scope.scopeVerdict` | `unit-tested` | 5:1 boundary acceptable; below insufficient |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `19/19 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: K-factor table flagged `claimed`;
  supplier-specific anchor data may give different values within
  the same nominal class. The Stevin 0.92 power-law fit is empirical
  in firm seabed conditions; soft seabed reduces capacity.
- Type-II missed risk guard: typed-error rejection for zero anchor
  weight / friction / L_floor / depth, scope < 3:1.
- Type-III category guard: holding-power + scope-geometry kernel
  only; not a catenary cable-shape solver (use `yard-mooring-zig`);
  not an anchor-drag analyser; not a cyclic-load amplifier; not a
  windlass / winch sizing tool.

## What is not covered (v0.0.0)

- Seabed-type-specific adjustment beyond mu.
- Anchor-drag while holding.
- Cyclic / dynamic load amplification.
- Catenary cable shape (use `yard-mooring-zig`).
- Anchor handling / winch sizing.
- Type-specific anchor catalogue.

## Composition

- Output `H_total` composes with `yard-mooring-zig` catenary
  inverse-solver for the horizontal-force input at the fairlead.
- Compose with `yard-windaero-zig` and `yard-resistance-zig` static
  wind / current force for the loading side of the anchor balance.
