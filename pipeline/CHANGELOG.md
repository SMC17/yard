# Changelog

## [0.0.1] 2026-05-30

### Added

- `cable_route_consumer` module: reads an oceanman per-cable JSON
  record + optional landing-point-geo FeatureCollection, emits a
  geometry-only `LayPlan` (waypoints + great-circle segment lengths
  in kilometres + `depth_profile_present` honest signal).
- `oceanman-smoke` executable + `scripts/oceanman_smoke.sh` smoke
  gate (default cable `aden-djibouti`, 30-run median parse under
  the 100 ms gate).
- 7 tests covering cable parse, landing-coord resolution, hand-
  computed great-circle (Djibouti City to Aden, ~244.9 km vs ~269
  km quoted cable length), and typed-error rejection for missing
  id / empty landings / invalid JSON. 20/20 tests pass.
- CONTRIBUTING.md with AI-codegen contributor discipline.

### Disclosure (load-bearing)

A submarine telecommunications cable record is NOT a subsea-
pipeline lay plan. The wire surfaces SHARED maritime route
geometry only. Per-KP bathymetry, soil class, vessel tension
envelope, and DNV-RP-F109 on-bottom stability do not transfer.

### Verdict

Pre-registered experiment exp-1780164252-902382970 confirmed:
median parse < 100 ms on real oceanman aden-djibouti record;
non-empty LayPlan with 2 resolved waypoints + 1 great-circle
segment.

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `stability.dragForcePerLengthNM` Morison drag.
- `stability.inertiaForcePerLengthNM` Morison inertia.
- `stability.liftForcePerLengthNM` lift.
- `stability.requiredSubmergedWeightNM` lateral-static balance.
- `stability.verdict` pass / fail.
- 13-test unit suite including 1230 N/m drag, 922.5 N/m lift,
  3628.5 N/m required weight composed example, SF and 1/mu
  scaling, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
