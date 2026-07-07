const std = @import("std");

pub const Error = error{
    NonPositiveCapacity,
    NonPositiveBreadth,
    NonPositiveDistance,
};

/// Tank capacity threshold below which Reg. 12A does not apply [m^3].
pub const capacity_threshold_m3: f64 = 600.0;

/// Required side distance per Reg. 12A.4.1:
///   w = 0.4 + 2.4 C / 20000  [m]
/// clamped to the range [1.0, 2.0] m.
pub fn requiredSideDistanceM(C_m3: f64) Error!f64 {
    if (!(C_m3 > 0)) return Error.NonPositiveCapacity;
    if (C_m3 < capacity_threshold_m3) return 0.0;
    var w = 0.4 + 2.4 * C_m3 / 20000.0;
    if (w < 1.0) w = 1.0;
    if (w > 2.0) w = 2.0;
    return w;
}

/// Required double-bottom height per Reg. 12A.4.2:
///   h = max(B/20, 2.0 m)
/// clamped to a maximum of 2.0 m (and a minimum of 0.76 m for
/// small ships, but Reg. 12A explicitly applies for C >= 600 m^3
/// vessels typically larger than the 0.76 m threshold). Returns 0
/// if C is below the regulation threshold.
pub fn requiredDoubleBottomHeightM(C_m3: f64, B_m: f64) Error!f64 {
    if (!(C_m3 > 0)) return Error.NonPositiveCapacity;
    if (!(B_m > 0)) return Error.NonPositiveBreadth;
    if (C_m3 < capacity_threshold_m3) return 0.0;
    var h = B_m / 20.0;
    if (h < 2.0) h = 2.0;
    if (h > 2.0) h = 2.0;
    return h;
}

pub const Verdict = enum {
    /// Arrangement satisfies both side- and bottom-distance
    /// requirements.
    pass,
    /// Side or bottom distance below required minimum.
    fail,
};

pub fn complianceVerdict(
    actual_side_m: f64,
    actual_bottom_m: f64,
    required_side_m: f64,
    required_bottom_m: f64,
) Error!Verdict {
    if (!(actual_side_m >= 0)) return Error.NonPositiveDistance;
    if (!(actual_bottom_m >= 0)) return Error.NonPositiveDistance;
    if (actual_side_m < required_side_m) return .fail;
    if (actual_bottom_m < required_bottom_m) return .fail;
    return .pass;
}

test "below 600 m^3 threshold: zero required" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try requiredSideDistanceM(500.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try requiredDoubleBottomHeightM(500.0, 30.0), 1e-12);
}

test "side distance at C = 1000 m^3 is 0.4 + 0.12 = 0.52, clamped to 1.0" {
    const w = try requiredSideDistanceM(1000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), w, 1e-12);
}

test "side distance at C = 5000 m^3 is 0.4 + 0.6 = 1.0 (lower clamp boundary)" {
    const w = try requiredSideDistanceM(5000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), w, 1e-12);
}

test "side distance at C = 10000 m^3 is 0.4 + 1.2 = 1.6" {
    const w = try requiredSideDistanceM(10000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.6), w, 1e-12);
}

test "side distance at C = 13333 m^3 is 0.4 + 1.6 = 2.0 (upper clamp)" {
    const w = try requiredSideDistanceM(13333.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), w, 1e-3);
}

test "side distance at C = 50000 m^3 is clamped to 2.0" {
    const w = try requiredSideDistanceM(50000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), w, 1e-12);
}

test "double-bottom height at B = 30 m, C = 5000: B/20 = 1.5 -> clamped 2.0" {
    const h = try requiredDoubleBottomHeightM(5000.0, 30.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), h, 1e-12);
}

test "double-bottom height at B = 50 m: would be 2.5 -> clamped 2.0" {
    const h = try requiredDoubleBottomHeightM(5000.0, 50.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), h, 1e-12);
}

test "compliance verdict pass when actual >= required" {
    try std.testing.expectEqual(Verdict.pass, try complianceVerdict(2.0, 2.0, 1.6, 2.0));
}

test "compliance verdict fail when actual side < required" {
    try std.testing.expectEqual(Verdict.fail, try complianceVerdict(1.5, 2.0, 1.6, 2.0));
}

test "compliance verdict fail when actual bottom < required" {
    try std.testing.expectEqual(Verdict.fail, try complianceVerdict(2.0, 1.8, 1.6, 2.0));
}

test "input rejection: zero capacity" {
    try std.testing.expectError(Error.NonPositiveCapacity, requiredSideDistanceM(0.0));
}

test "input rejection: zero breadth" {
    try std.testing.expectError(Error.NonPositiveBreadth, requiredDoubleBottomHeightM(5000.0, 0.0));
}

test "input rejection: negative actual distance" {
    try std.testing.expectError(Error.NonPositiveDistance, complianceVerdict(-1.0, 2.0, 1.6, 2.0));
}
