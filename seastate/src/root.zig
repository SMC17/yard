//! yard-seastate — wind/sea-state glue, per the published scales:
//!
//! - Beaufort force from 10-m wind speed, WMO Manual on Codes (code 1100)
//!   band upper limits in m/s.
//! - Pierson-Moskowitz (1964) fully developed sea:
//!     Hs = 0.21 U^2 / g,  Tp = 2 pi U / (0.877 g)
//!   (fully developed = unlimited fetch/duration; an upper envelope for
//!   growing seas, stated as such wherever consumed).
//! - Douglas sea state (WMO code 3700) from Hs.
//!
//! Proof level: unit-tested (published band edges and formula hand-checks).

const std = @import("std");

pub const g: f64 = 9.80665;

/// WMO Beaufort band upper limits [m/s], forces 0..11 (12 = above).
const beaufort_upper = [_]f64{ 0.5, 1.5, 3.3, 5.5, 7.9, 10.7, 13.8, 17.1, 20.7, 24.4, 28.4, 32.6 };

pub fn beaufortForce(wind_mps: f64) u8 {
    for (beaufort_upper, 0..) |limit, force| {
        if (wind_mps <= limit) return @intCast(force);
    }
    return 12;
}

/// Fully developed significant wave height [m] for 10-m wind U [m/s].
pub fn pmSignificantHeight(u_mps: f64) f64 {
    return 0.21 * u_mps * u_mps / g;
}

/// Fully developed peak period [s].
pub fn pmPeakPeriod(u_mps: f64) f64 {
    return 2.0 * std.math.pi * u_mps / (0.877 * g);
}

/// Douglas sea state code (WMO 3700) upper Hs limits [m], states 0..8.
const douglas_upper = [_]f64{ 0.0, 0.1, 0.5, 1.25, 2.5, 4.0, 6.0, 9.0, 14.0 };

pub fn douglasSeaState(hs_m: f64) u8 {
    for (douglas_upper, 0..) |limit, state| {
        if (hs_m <= limit) return @intCast(state);
    }
    return 9;
}

test "Beaufort bands match WMO edges" {
    try std.testing.expectEqual(@as(u8, 0), beaufortForce(0.4));
    try std.testing.expectEqual(@as(u8, 4), beaufortForce(7.9));
    try std.testing.expectEqual(@as(u8, 5), beaufortForce(8.0));
    try std.testing.expectEqual(@as(u8, 8), beaufortForce(20.7));
    try std.testing.expectEqual(@as(u8, 12), beaufortForce(33.0));
}

test "Pierson-Moskowitz hand checks" {
    // U = 20 m/s: Hs = 0.21*400/9.80665 = 8.566 m.
    try std.testing.expectApproxEqAbs(@as(f64, 8.5656), pmSignificantHeight(20.0), 1e-3);
    // U = 10 m/s: Hs = 2.141 m, Tp = 2 pi 10 / 8.601 = 7.305 s.
    try std.testing.expectApproxEqAbs(@as(f64, 2.1414), pmSignificantHeight(10.0), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f64, 7.3054), pmPeakPeriod(10.0), 1e-3);
    // Quadratic growth in wind.
    try std.testing.expectApproxEqRel(@as(f64, 4.0), pmSignificantHeight(20.0) / pmSignificantHeight(10.0), 1e-12);
}

test "Douglas states follow Hs" {
    try std.testing.expectEqual(@as(u8, 3), douglasSeaState(1.0));
    try std.testing.expectEqual(@as(u8, 4), douglasSeaState(2.5));
    try std.testing.expectEqual(@as(u8, 6), douglasSeaState(5.0));
    try std.testing.expectEqual(@as(u8, 9), douglasSeaState(15.0));
}
