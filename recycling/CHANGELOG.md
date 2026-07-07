# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `hkc.capacityUtilisation`, `applicabilityForYear`,
  `euSrrApplicable`, `proceedsUSD`.
- `hkc.hkc_entry_into_force_year = 2025`.
- `ihm.HazardousMaterial` enum with 12 substances.
- `ihm.IHMEntry`, `concentrationFraction`, `entryVerdict`,
  `totalIHMMassKg`, `failingEntryCount`.
- `recovery.MaterialCategory` enum with 7 categories summing to 1.0.
- `recovery.recoveredMassT`, `totalRecoveredT`,
  `categoryProceedsUSD`, `hazardousDisposalCostUSD`.
- 37-test unit suite covering capacity utilisation, HKC year
  applicability, EU SRR flag-state gate, IHM concentration + max
  fraction comparison (asbestos prohibited; lead at 0.1 % boundary),
  failing-entry count, recovery fractions summing to 1.0, and
  category proceeds.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
