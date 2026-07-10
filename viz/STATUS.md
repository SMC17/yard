# Status

yard-viz-zig v0.1.0. Pre-1.0; bound by Zig 0.16 per `~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `gz_svg` | `unit-tested` | valid SVG polyline + empty-points rejection |
| `pareto_svg` | `unit-tested` | scatter + front polyline render |
| `hull_profile_svg` | `unit-tested` | Wigley waterline + midship profile SVG |

## Composition

Deterministic SVG export for compose workflows and dataset tooling (no GPU deps).