# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `throughput.annualThroughputTEU`, `effectiveBerthHoursPerYear`,
  `movesPerHour`, `throughputPerQuayMeter`.
- `dwell.littleLawAverageInYard`, `yardSlotsRequired`,
  `DwellMix` + `weightedDwellHr`, `annualMovesPerGroundSlot`.
- `truck.erlangC`, `averageWaitHr`, `averageQueueLength`,
  `timeOfDayMultiplier`.
- 37-test unit suite including 1.6 M TEU annual closed form, 7200
  TEU Little's Law, 8760/dwell ground-slot reuse, Erlang-C in (0,1),
  Erlang-C monotonic with utilisation, time-of-day half-distance
  factor = 1, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
