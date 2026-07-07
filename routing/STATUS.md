# Status

yard-routing-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `great_circle.haversineDistanceM` | `unit-tested` | pole-to-equator = pi/2 R; antipodal = pi R; unit-sphere central angle; JFK-LHR within published 5539 km value |
| `great_circle.initialBearingRad` | `unit-tested` | cardinal north/east/south/west exact closed forms |
| `great_circle.crossTrackDistanceM` | `unit-tested` | parallel-path equator case zero cross-track |
| `rhumb_line.rhumbDistanceM` | `unit-tested` | equator and meridian routes reduce to arc length; rhumb >= great-circle for non-equatorial; antimeridian wrap 170 E -> 170 W = 20 deg |
| `rhumb_line.rhumbBearingRad` | `unit-tested` | cardinal directions; antimeridian wrap east case |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `22/22 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: caller-supplied radius defends against
  silent mixing of spherical / ellipsoidal regimes. The constant
  `earth_radius_m` is explicit and documented as a spherical
  approximation; the kernel never silently assumes an ellipsoid.
- Type-II missed risk guard: antimeridian wrap in rhumb-line bearing
  and distance prevents the +/-180 degree boundary from producing
  the wrong way around.
- Type-III category guard: spherical-geodesy kernel only; not a
  weather-routing engine; not a tidal/current-aware optimizer; not
  a Vincenty-on-ellipsoid solver.

## What is not covered (v0.0.0)

- WGS-84 ellipsoidal (Vincenty) geodesy.
- Mercator / UTM projections.
- Multi-leg route generation.
- Iso-chrone weather routing.
- Currents / tides overlay.
- Collision-avoidance bearing rate.

## Composition

- Spherical distance enables `yard-eedi-zig` and similar voyage
  fuel-consumption models to compute V_ref * t leg distances.
- Composes with `yard-ais-zig` to convert AIS position reports into
  range/bearing pairs for traffic-density studies.
