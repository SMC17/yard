# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `great_circle.haversineDistanceM`.
- `great_circle.initialBearingRad`.
- `great_circle.crossTrackDistanceM`.
- `rhumb_line.rhumbDistanceM`.
- `rhumb_line.rhumbBearingRad`.
- `earth_radius_m` and `nautical_mile_m` package constants.
- 22-test unit suite including pole-equator, antipodal, unit-sphere,
  JFK-LHR, cardinal-direction bearings, and antimeridian wrap.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
