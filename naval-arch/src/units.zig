//! Unit conversions used across yard composition workflows.

const std = @import("std");

pub fn degToRad(deg: f64) f64 {
    return deg * std.math.pi / 180.0;
}

pub fn radToDeg(rad: f64) f64 {
    return rad * 180.0 / std.math.pi;
}

pub fn knotsToMps(knots: f64) f64 {
    return knots * 0.514444;
}

pub fn mpsToKnots(mps: f64) f64 {
    return mps / 0.514444;
}

test "deg rad roundtrip" {
    try std.testing.expectApproxEqAbs(@as(f64, 30.0), radToDeg(degToRad(30.0)), 1e-12);
}