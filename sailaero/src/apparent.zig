//! Apparent wind from true wind and boat velocity. Exact vector math.
//!
//! Conventions: true wind angle (TWA) and apparent wind angle (AWA) are
//! measured from the bow, 0 = head to wind, 180 = dead run, degrees.
//! Speeds in m/s.

const std = @import("std");

pub const Apparent = struct {
    speed_mps: f64,
    angle_deg: f64,
};

pub fn compute(true_wind_mps: f64, true_angle_deg: f64, boat_speed_mps: f64) Apparent {
    const twa = std.math.degreesToRadians(true_angle_deg);
    // Wind components in the boat frame: x forward, y to the side the wind
    // comes over. Boat motion adds a headwind component.
    const wx = true_wind_mps * @cos(twa) + boat_speed_mps;
    const wy = true_wind_mps * @sin(twa);
    const aws = @sqrt(wx * wx + wy * wy);
    const awa = std.math.atan2(wy, wx);
    return .{
        .speed_mps = aws,
        .angle_deg = std.math.radiansToDegrees(awa),
    };
}

test "head to wind: speeds add" {
    const a = compute(10.0, 0.0, 3.0);
    try std.testing.expectApproxEqAbs(@as(f64, 13.0), a.speed_mps, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), a.angle_deg, 1e-12);
}

test "dead run: speeds subtract" {
    const a = compute(10.0, 180.0, 3.0);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), a.speed_mps, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 180.0), @abs(a.angle_deg), 1e-9);
}

test "beam wind: pythagorean and forward-shifted" {
    const a = compute(4.0, 90.0, 3.0);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 25.0)), a.speed_mps, 1e-12);
    // atan2(4, 3) = 53.13 deg: apparent wind moves forward of the beam.
    try std.testing.expectApproxEqAbs(@as(f64, 53.13010235415598), a.angle_deg, 1e-9);
    try std.testing.expect(a.angle_deg < 90.0);
}

test "stationary boat sees true wind" {
    const a = compute(8.0, 123.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), a.speed_mps, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 123.0), a.angle_deg, 1e-9);
}
