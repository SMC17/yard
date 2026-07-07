# yard-routing-zig

Proof level: `unit-tested`

yard-routing-zig is a Zig 0.16 spherical-geodesy kernel. Haversine
great-circle distance and initial bearing; rhumb-line (loxodrome)
constant-bearing distance and bearing; cross-track distance. Sphere
model with caller-supplied radius; the package constant
`earth_radius_m` defaults to the WGS-84 mean spherical radius of
6,371,000 m.

## What it does

- `great_circle.haversineDistanceM(lat1, lon1, lat2, lon2, R)` returns
  the shortest-path distance via the haversine formula.
- `great_circle.initialBearingRad(lat1, lon1, lat2, lon2)` returns the
  initial bearing from north, range [0, 2 pi).
- `great_circle.crossTrackDistanceM(d_SP, bearing_S, bearing_SP, R)`
  signed cross-track distance from a point P to a great-circle path.
- `rhumb_line.rhumbDistanceM(lat1, lon1, lat2, lon2, R)` constant-
  bearing rhumb-line distance via Mercator inverse-Gudermannian.
- `rhumb_line.rhumbBearingRad(lat1, lon1, lat2, lon2)` constant rhumb
  bearing, with antimeridian wrap.
- `earth_radius_m` and `nautical_mile_m` package constants.

## What it is not (v0.0.0)

- No WGS-84 ellipsoidal (Vincenty) geodesy. The kernel is spherical.
- No Mercator / UTM grid projection.
- No multi-leg great-circle route generation (caller composes legs).
- No iso-chrone weather routing.
- No tidal / current overlay.
- No collision-avoidance bearing-rate computation.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 22/22 tests passed`.

## Public API

```zig
const yard = @import("yard_routing");
const deg2rad: f64 = std.math.pi / 180.0;

const lat1 = 40.6413 * deg2rad;
const lon1 = -73.7781 * deg2rad;
const lat2 = 51.4700 * deg2rad;
const lon2 = -0.4543 * deg2rad;

const d_gc = try yard.great_circle.haversineDistanceM(
    lat1, lon1, lat2, lon2, yard.earth_radius_m);
const b_gc = try yard.great_circle.initialBearingRad(
    lat1, lon1, lat2, lon2);
const d_rh = try yard.rhumb_line.rhumbDistanceM(
    lat1, lon1, lat2, lon2, yard.earth_radius_m);
```

## Validation

- Haversine: north-pole-to-equator on prime meridian equals
  `pi/2 * R` to 1e-6.
- Haversine: antipodal points are `pi R` apart.
- Haversine: identical points yield zero.
- Haversine on a unit sphere matches the central angle of two
  equatorial points 60 degrees apart.
- Initial bearing: cardinal directions north (0), east (pi/2),
  south (pi), west (3 pi / 2).
- JFK (40.6413 N, 73.7781 W) to LHR (51.4700 N, 0.4543 W): distance
  within [5500, 5600] km (independent value 5538.7 km).
- Rhumb on equator and along meridian reduces to arc length.
- Rhumb distance is greater than or equal to great-circle distance
  for non-equatorial routes.
- Rhumb bearing wraps correctly across the antimeridian
  (170 E to 170 W is east, distance 20 degrees on the equator).
- Typed-error rejection for out-of-range latitude / longitude and
  non-positive radius.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Bowditch, N. (2017). *The American Practical Navigator*.
  NIMA Pub. No. 9.
- Veness, C. (2002). *Movable Type calculations for geodesy*
  (haversine reference).
- Williams, E. (1996). *Aviation Formulary V1.46*.

## License

Apache-2.0.
