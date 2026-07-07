const std = @import("std");

pub const Error = error{
    NonPositiveDepth,
    NonPositiveScope,
};

/// Recommended scope ratio (cable length / water depth) for adequate
/// holding. Standard practice: 5:1 to 7:1 in moderate weather;
/// >= 10:1 for heavy weather or storm anchoring.
pub const recommended_scope_moderate: f64 = 7.0;
pub const recommended_scope_storm: f64 = 10.0;

/// Minimum cable length to deploy for a given water depth at the
/// recommended scope ratio.
pub fn minimumCableLengthM(
    water_depth_m: f64,
    scope_ratio: f64,
) Error!f64 {
    if (!(water_depth_m > 0)) return Error.NonPositiveDepth;
    if (!(scope_ratio >= 3.0)) return Error.NonPositiveScope;
    return water_depth_m * scope_ratio;
}

/// Actual scope ratio achieved with a given cable length and depth.
pub fn scopeRatio(cable_length_m: f64, water_depth_m: f64) Error!f64 {
    if (!(water_depth_m > 0)) return Error.NonPositiveDepth;
    if (!(cable_length_m > 0)) return Error.NonPositiveScope;
    return cable_length_m / water_depth_m;
}

pub const Verdict = enum {
    /// Scope >= 5:1: minimum acceptable.
    acceptable,
    /// Scope < 5:1: cable too short to ensure horizontal shank
    /// loading; anchor likely to break out.
    insufficient,
};

pub fn scopeVerdict(scope: f64) Verdict {
    if (scope >= 5.0) return .acceptable;
    return .insufficient;
}

test "minimum cable at 30 m depth, 7:1 scope = 210 m" {
    const L = try minimumCableLengthM(30.0, 7.0);
    try std.testing.expectApproxEqAbs(@as(f64, 210.0), L, 1e-12);
}

test "minimum cable at 30 m depth, 10:1 storm scope = 300 m" {
    const L = try minimumCableLengthM(30.0, recommended_scope_storm);
    try std.testing.expectApproxEqAbs(@as(f64, 300.0), L, 1e-12);
}

test "scope ratio: L = 210 m at h = 30 m equals 7" {
    const s = try scopeRatio(210.0, 30.0);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), s, 1e-12);
}

test "verdict acceptable at scope = 5" {
    try std.testing.expectEqual(Verdict.acceptable, scopeVerdict(5.0));
}

test "verdict acceptable at scope = 10" {
    try std.testing.expectEqual(Verdict.acceptable, scopeVerdict(10.0));
}

test "verdict insufficient at scope = 4" {
    try std.testing.expectEqual(Verdict.insufficient, scopeVerdict(4.0));
}

test "input rejection: zero depth" {
    try std.testing.expectError(Error.NonPositiveDepth, minimumCableLengthM(0.0, 5.0));
}

test "input rejection: scope ratio < 3" {
    try std.testing.expectError(Error.NonPositiveScope, minimumCableLengthM(30.0, 2.0));
}
