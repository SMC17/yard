# yard-cargo-zig

Proof level: `unit-tested`

yard-cargo-zig is a Zig 0.16 cargo-handling kernel covering container
stowage, breakbulk stowage factor, and project-cargo / heavy-lift
sling + cribbing + deck-pressure check.

## What it does

### Container (ISO 668)

- `container.ContainerSize` (TEU_20ft / FEU_40ft / HC_45ft) with
  length / TEU / max gross / typical tare / max payload.
- `container.stackingWeightN(tiers, m_gross, g)` returns
  `(tiers - 1) m_gross g`.
- `container.perCornerPostLoadN(W_stack)` returns `W_stack / 4`.
- `container.csc_stacking_rating_per_post_n = 96000 g` per ISO
  1496-1.
- `container.stackingVerdict(F_post)` pass / fail.
- `container.bayTeuCount(rows, tiers)` returns `rows * tiers`.

### Breakbulk

- `breakbulk.CargoClass` enum with 9 classes and stowage factors:
  grain 1.45, iron ore 0.40, coal 1.20, cement 0.65, steel 0.40,
  bagged sugar 1.30, palletised general 1.80, crude oil 1.10,
  LNG 2.20.
- `breakbulk.requiredHoldVolumeM3(m, cls, broken_stowage)` returns
  `m SF (1 + bs)`.
- `breakbulk.maxLoadableMassT(V, cls, broken_stowage)` inverse.
- `breakbulk.loadDensityTPerM3(cls)` returns `1 / SF`.

### Project cargo / heavy lift

- `project.slingLegTensionN(m, g, n, theta)` returns
  `m g / (n cos theta)`.
- `project.slingAngleFactor(theta)` returns `1 / cos(theta)`.
- `project.slingVerdict(T, SWL)` pass / fail.
- `project.cribReactionN(m, g, N)` returns `m g / N`.
- `project.deckPressurePa(m, g, A)` returns `m g / A`.
- `project.DeckType` (weather_tween / tank_top / heavy_lift_strip)
  with allowable 49 kPa / 294 kPa / 1 MPa.
- `project.deckPressureVerdict(p, deck)` pass / fail.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 43/43 tests passed`.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- ISO 668. *Series 1 freight containers - Classification, dimensions
  and ratings*.
- ISO 1496-1. *Series 1 freight containers - Specification and
  testing*.
- Stevens, A. J. (2000). *Stowage: The Properties and Stowage of
  Cargoes*. The Nautical Institute.
- IMO CSS Code. *Code of Safe Practice for Cargo Stowage and
  Securing*.

## License

AGPL-3.0-or-later.
