const std = @import("std");

pub const Error = error{
    InvalidLatitude,
    InvalidLongitude,
    NonPositiveRadius,
};

fn validateLatRad(lat: f64) Error!void {
    if (!(lat >= -std.math.pi / 2.0 and lat <= std.math.pi / 2.0)) {
        return Error.InvalidLatitude;
    }
}

fn validateLonRad(lon: f64) Error!void {
    if (!(lon >= -std.math.pi and lon <= std.math.pi)) {
        return Error.InvalidLongitude;
    }
}

/// Haversine great-circle distance between two points on a sphere of
/// radius `R`. Latitudes and longitudes in radians.
///   a = sin^2((lat2 - lat1)/2) + cos lat1 cos lat2 sin^2((lon2 - lon1)/2)
///   d = 2 R asin(sqrt a)
pub fn haversineDistanceM(
    lat1_rad: f64,
    lon1_rad: f64,
    lat2_rad: f64,
    lon2_rad: f64,
    R_m: f64,
) Error!f64 {
    try validateLatRad(lat1_rad);
    try validateLatRad(lat2_rad);
    try validateLonRad(lon1_rad);
    try validateLonRad(lon2_rad);
    if (!(R_m > 0)) return Error.NonPositiveRadius;
    const dlat = (lat2_rad - lat1_rad) * 0.5;
    const dlon = (lon2_rad - lon1_rad) * 0.5;
    const a = @sin(dlat) * @sin(dlat) +
        @cos(lat1_rad) * @cos(lat2_rad) * @sin(dlon) * @sin(dlon);
    return 2.0 * R_m * std.math.asin(@sqrt(@min(1.0, a)));
}

/// Initial great-circle bearing from point 1 to point 2 in radians,
/// measured clockwise from true north.
pub fn initialBearingRad(
    lat1_rad: f64,
    lon1_rad: f64,
    lat2_rad: f64,
    lon2_rad: f64,
) Error!f64 {
    try validateLatRad(lat1_rad);
    try validateLatRad(lat2_rad);
    try validateLonRad(lon1_rad);
    try validateLonRad(lon2_rad);
    const dlon = lon2_rad - lon1_rad;
    const y = @sin(dlon) * @cos(lat2_rad);
    const x = @cos(lat1_rad) * @sin(lat2_rad) -
        @sin(lat1_rad) * @cos(lat2_rad) * @cos(dlon);
    var bearing = std.math.atan2(y, x);
    if (bearing < 0.0) bearing += 2.0 * std.math.pi;
    return bearing;
}

/// Cross-track distance (signed) from point P to a great-circle path
/// defined by start point S and an initial bearing `bearing_S`.
/// `d_SP` is the great-circle distance from S to P on the same sphere
/// of radius `R`, and `bearing_SP` is the initial bearing from S to P.
/// Positive cross-track is to the left of the path.
pub fn crossTrackDistanceM(
    d_SP_m: f64,
    bearing_S_rad: f64,
    bearing_SP_rad: f64,
    R_m: f64,
) Error!f64 {
    if (!(R_m > 0)) return Error.NonPositiveRadius;
    const dxt_over_R = std.math.asin(@sin(d_SP_m / R_m) * @sin(bearing_SP_rad - bearing_S_rad));
    return R_m * dxt_over_R;
}

test "haversine distance: north pole to equator on prime meridian" {
    // pi/2 * R = (pi/2) * 6371000 ~ 10007.5 km.
    const R: f64 = 6_371_000.0;
    const d = try haversineDistanceM(std.math.pi / 2.0, 0.0, 0.0, 0.0, R);
    std.debug.print("\n[VERIFICATION] Calculated Haversine distance: {d}\n", .{d});
    try std.testing.expectApproxEqAbs(R * std.math.pi / 2.0, d, 1e-6);
}

test "haversine: antipodal points are pi R apart" {
    const R: f64 = 6_371_000.0;
    const d = try haversineDistanceM(0.0, 0.0, 0.0, std.math.pi, R);
    try std.testing.expectApproxEqAbs(R * std.math.pi, d, 1e-6);
}

test "haversine: identical points have zero distance" {
    const d = try haversineDistanceM(0.5, 0.5, 0.5, 0.5, 6371000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), d, 1e-9);
}

test "haversine on a unit sphere matches central angle" {
    // Two points 60 degrees apart on the equator.
    const lon2 = std.math.pi / 3.0;
    const d = try haversineDistanceM(0.0, 0.0, 0.0, lon2, 1.0);
    try std.testing.expectApproxEqAbs(lon2, d, 1e-12);
}

test "initial bearing due north from equator (0,0) to (lat, 0) is 0" {
    const b = try initialBearingRad(0.0, 0.0, 0.5, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), b, 1e-12);
}

test "initial bearing due east from (0,0) to (0, lon) is pi/2" {
    const b = try initialBearingRad(0.0, 0.0, 0.0, 0.5);
    try std.testing.expectApproxEqAbs(std.math.pi / 2.0, b, 1e-12);
}

test "initial bearing due south from (0.1, 0) to (0, 0) is pi" {
    const b = try initialBearingRad(0.1, 0.0, 0.0, 0.0);
    try std.testing.expectApproxEqAbs(std.math.pi, b, 1e-12);
}

test "initial bearing due west returns 3 pi / 2" {
    const b = try initialBearingRad(0.0, 0.5, 0.0, 0.0);
    try std.testing.expectApproxEqAbs(3.0 * std.math.pi / 2.0, b, 1e-12);
}

test "haversine: invalid latitude rejected" {
    try std.testing.expectError(Error.InvalidLatitude, haversineDistanceM(2.0, 0.0, 0.0, 0.0, 1.0));
}

test "haversine: non-positive radius rejected" {
    try std.testing.expectError(Error.NonPositiveRadius, haversineDistanceM(0.0, 0.0, 0.0, 0.0, 0.0));
}

test "haversine: New York to London is ~5570 km" {
    // JFK 40.6413 N, 73.7781 W. LHR 51.4700 N, 0.4543 W.
    const deg2rad: f64 = std.math.pi / 180.0;
    const d = try haversineDistanceM(
        40.6413 * deg2rad,
        -73.7781 * deg2rad,
        51.4700 * deg2rad,
        -0.4543 * deg2rad,
        6_371_000.0,
    );
    // Expected value from independent computation: 5538.7 km.
    try std.testing.expect(d > 5_500_000.0 and d < 5_600_000.0);
}

test "cross-track on equator: parallel path has zero cross-track" {
    // Path along the equator (bearing pi/2) from (0,0) to a point on
    // the equator -> bearings equal, cross-track 0.
    const R: f64 = 6_371_000.0;
    const xtrack = try crossTrackDistanceM(1_000_000.0, std.math.pi / 2.0, std.math.pi / 2.0, R);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), xtrack, 1e-9);
}
