const std = @import("std");

pub const Error = error{
    InvalidLatitude,
    NonPositiveRadius,
};

fn validateLatRad(lat: f64) Error!void {
    if (!(lat >= -std.math.pi / 2.0 and lat <= std.math.pi / 2.0)) {
        return Error.InvalidLatitude;
    }
}

/// Rhumb-line (loxodrome) distance between two points on a sphere of
/// radius `R`. Latitudes and longitudes in radians.
///   dphi = ln(tan(pi/4 + lat2/2) / tan(pi/4 + lat1/2))
///   q    = (lat2 - lat1) / dphi if |dphi| > eps, else cos(lat1)
///   d    = R sqrt((lat2 - lat1)^2 + (q dlon)^2)
pub fn rhumbDistanceM(
    lat1_rad: f64,
    lon1_rad: f64,
    lat2_rad: f64,
    lon2_rad: f64,
    R_m: f64,
) Error!f64 {
    try validateLatRad(lat1_rad);
    try validateLatRad(lat2_rad);
    if (!(R_m > 0)) return Error.NonPositiveRadius;
    const dlat = lat2_rad - lat1_rad;
    var dlon = lon2_rad - lon1_rad;
    // Wrap dlon into (-pi, +pi].
    while (dlon > std.math.pi) dlon -= 2.0 * std.math.pi;
    while (dlon < -std.math.pi) dlon += 2.0 * std.math.pi;
    const dphi = @log(
        @tan(std.math.pi / 4.0 + lat2_rad * 0.5) /
            @tan(std.math.pi / 4.0 + lat1_rad * 0.5),
    );
    const q: f64 = if (@abs(dphi) > 1e-12)
        dlat / dphi
    else
        @cos(lat1_rad);
    return R_m * @sqrt(dlat * dlat + q * q * dlon * dlon);
}

/// Rhumb-line constant bearing from point 1 to point 2 in radians,
/// measured clockwise from true north.
pub fn rhumbBearingRad(
    lat1_rad: f64,
    lon1_rad: f64,
    lat2_rad: f64,
    lon2_rad: f64,
) Error!f64 {
    try validateLatRad(lat1_rad);
    try validateLatRad(lat2_rad);
    var dlon = lon2_rad - lon1_rad;
    while (dlon > std.math.pi) dlon -= 2.0 * std.math.pi;
    while (dlon < -std.math.pi) dlon += 2.0 * std.math.pi;
    const dphi = @log(
        @tan(std.math.pi / 4.0 + lat2_rad * 0.5) /
            @tan(std.math.pi / 4.0 + lat1_rad * 0.5),
    );
    var b = std.math.atan2(dlon, dphi);
    if (b < 0.0) b += 2.0 * std.math.pi;
    return b;
}

test "rhumb distance on equator equals arc length" {
    const R: f64 = 6_371_000.0;
    const d = try rhumbDistanceM(0.0, 0.0, 0.0, 1.0, R);
    try std.testing.expectApproxEqAbs(R * 1.0, d, 1e-6);
}

test "rhumb distance along meridian equals arc length" {
    const R: f64 = 6_371_000.0;
    const d = try rhumbDistanceM(0.0, 0.0, 0.5, 0.0, R);
    try std.testing.expectApproxEqAbs(R * 0.5, d, 1e-6);
}

test "rhumb identical points have zero distance" {
    const d = try rhumbDistanceM(0.5, 0.5, 0.5, 0.5, 6_371_000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), d, 1e-9);
}

test "rhumb bearing due east on equator is pi/2" {
    const b = try rhumbBearingRad(0.0, 0.0, 0.0, 0.5);
    try std.testing.expectApproxEqAbs(std.math.pi / 2.0, b, 1e-12);
}

test "rhumb bearing due north along meridian is 0" {
    const b = try rhumbBearingRad(0.0, 0.0, 0.5, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), b, 1e-12);
}

test "rhumb bearing due south is pi" {
    const b = try rhumbBearingRad(0.5, 0.0, 0.0, 0.0);
    try std.testing.expectApproxEqAbs(std.math.pi, b, 1e-12);
}

test "rhumb >= great-circle distance" {
    // For non-equatorial routes the rhumb line is longer than the
    // great circle.
    const great_circle = @import("great_circle.zig");
    const R: f64 = 6_371_000.0;
    const lat1: f64 = 0.7; // ~40 N
    const lon1: f64 = -1.3;
    const lat2: f64 = 0.9; // ~52 N
    const lon2: f64 = -0.008;
    const d_gc = try great_circle.haversineDistanceM(lat1, lon1, lat2, lon2, R);
    const d_rh = try rhumbDistanceM(lat1, lon1, lat2, lon2, R);
    try std.testing.expect(d_rh >= d_gc - 1e-6);
}

test "rhumb bearing wraps east across antimeridian" {
    // 170 E to 170 W via the antimeridian is a short east bearing.
    const deg2rad: f64 = std.math.pi / 180.0;
    const b = try rhumbBearingRad(0.0, 170.0 * deg2rad, 0.0, -170.0 * deg2rad);
    try std.testing.expectApproxEqAbs(std.math.pi / 2.0, b, 1e-12);
}

test "rhumb distance via antimeridian is 20 degrees on equator" {
    const deg2rad: f64 = std.math.pi / 180.0;
    const R: f64 = 6_371_000.0;
    const d = try rhumbDistanceM(0.0, 170.0 * deg2rad, 0.0, -170.0 * deg2rad, R);
    try std.testing.expectApproxEqAbs(R * 20.0 * deg2rad, d, 1e-6);
}
