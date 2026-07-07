# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `berth.serviceTimeHr`, `berthUtilisation`, `annualCapacityCalls`,
  `utilisationVerdict` (UNCTAD 0.55-0.70 band).
- `gate.serverUtilisation`, `mm1QueueWaitHr`, `mm1QueueLength`,
  `mmcApproxQueueWaitHr`, `throughputPerHr`.
- `crane.netMovesPerHour` with dual-cycling uplift + loss fraction.
- `crane.multiCraneEfficiency`, `vesselMovesPerHr`.
- 43-test unit suite covering closed-form service time, capacity
  scaling, queueing wait blow-up, multi-crane interference monotone
  drop, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
