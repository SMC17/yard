// yard-routing-zig public API.
//
// great_circle: Haversine great-circle distance and initial bearing on
//               a spherical Earth model with caller-supplied radius.
//
// rhumb_line:   Rhumb-line (loxodrome) distance and constant bearing
//               via Mercator inverse Gudermannian transformation.

pub const great_circle = @import("great_circle.zig");
pub const rhumb_line = @import("rhumb_line.zig");

/// Mean Earth radius used by IMO and ITTC for nautical-mile distance
/// calculations: 6,371,000 m (the WGS-84 mean spherical radius).
pub const earth_radius_m: f64 = 6_371_000.0;

/// One nautical mile in metres (per the 1929 international definition
/// still in force).
pub const nautical_mile_m: f64 = 1852.0;

test {
    _ = great_circle;
    _ = rhumb_line;
}
