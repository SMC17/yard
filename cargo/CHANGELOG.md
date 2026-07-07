# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `container.ContainerSize` enum + length / TEU / mass / payload.
- `container.stackingWeightN`, `perCornerPostLoadN`,
  `stackingVerdict`, `bayTeuCount`.
- `container.csc_stacking_rating_per_post_n` 96 000 kg per ISO
  1496-1.
- `breakbulk.CargoClass` enum (9 classes) + stowage factors.
- `breakbulk.requiredHoldVolumeM3`, `maxLoadableMassT`,
  `loadDensityTPerM3`.
- `breakbulk.broken_stowage_*` named-constant defaults.
- `project.slingLegTensionN`, `slingAngleFactor`, `slingVerdict`.
- `project.cribReactionN`, `deckPressurePa`,
  `deckPressureVerdict`, `DeckType` enum.
- 43-test unit suite including container TEU / payload, stacking
  weight + CSC verdict, stowage-factor ordering, sling 0-deg /
  45-deg / 60-deg load factors, deck-pressure verdict by deck
  type, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

ISO 668 container values and Thomas's Stowage stowage-factor table
flagged `claimed`.
