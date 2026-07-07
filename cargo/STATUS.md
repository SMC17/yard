# Status

yard-cargo-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `container.ContainerSize.*` | `claimed` | ISO 668 + CSC values: 6.058 / 12.192 / 13.716 m; 30 480 / 32 500 kg max gross |
| `container.stackingWeightN` | `unit-tested` | (tiers - 1) m g; 980 665 N at 6 tiers / 20 t |
| `container.perCornerPostLoadN` | `unit-tested` | W / 4 |
| `container.stackingVerdict` | `unit-tested` | pass at 6-tier typical; fail at extreme overload |
| `container.bayTeuCount` | `unit-tested` | rows * tiers |
| `breakbulk.CargoClass` | `claimed` | Thomas's Stowage stowage-factor table |
| `breakbulk.requiredHoldVolumeM3` | `unit-tested` | 10000 t grain at 10 % broken stowage = 15 950 m^3 |
| `breakbulk.maxLoadableMassT` | `unit-tested` | inverse of requiredHoldVolumeM3 |
| `breakbulk.loadDensityTPerM3` | `unit-tested` | iron ore = 2.5; LNG = 0.4545 |
| `project.slingLegTensionN` | `unit-tested` | vertical = m g / n; 60 deg = 2 x vertical; 45 deg = sqrt(2) x vertical |
| `project.slingAngleFactor` | `unit-tested` | 1 / cos closed form |
| `project.slingVerdict` | `unit-tested` | <= SWL inclusive |
| `project.cribReactionN`, `deckPressurePa` | `unit-tested` | m g / N and m g / A closed forms |
| `project.DeckType.allowablePa` | `claimed` | weather 49 kPa; tank top 294 kPa; heavy-lift 1 MPa typical |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `43/43 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.
