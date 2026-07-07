const std = @import("std");

pub const Error = error{
    NonPositiveBollard,
    NonPositiveSpeed,
    InvalidSpeed,
};

/// Effective bollard pull at non-zero speed per Carlton 2018 fit:
///   BP(V) = BP_0 * max(0, 1 - V / V_max).
/// At V = V_max the bollard pull is zero (drag balances thrust).
pub fn bollardAtSpeedKN(BP_0_kN: f64, V_mps: f64, V_max_mps: f64) Error!f64 {
    if (!(BP_0_kN > 0)) return Error.NonPositiveBollard;
    if (!(V_max_mps > 0)) return Error.NonPositiveSpeed;
    if (!(V_mps >= 0)) return Error.InvalidSpeed;
    const f = 1.0 - V_mps / V_max_mps;
    if (f < 0.0) return 0.0;
    return BP_0_kN * f;
}

/// Typical V_max [m/s] per tug type (manufacturer indicative values).
pub fn typicalVMaxMPerS(ttype: anytype) f64 {
    return switch (ttype) {
        .Conventional => 5.0,
        .ASD => 7.0,
        .VSP => 6.5,
        .Escort => 8.0,
    };
}

/// Operating-class verdict: at the assisted-ship speed V, the
/// effective bollard pull must remain above a minimum required
/// pull for safe assistance.
pub const Verdict = enum { pass, fail };

pub fn assistanceVerdict(BP_eff_kN: f64, BP_required_kN: f64) Verdict {
    if (BP_eff_kN >= BP_required_kN) return .pass;
    return .fail;
}

test "bollard at zero speed equals BP_0" {
    const BP = try bollardAtSpeedKN(240.0, 0.0, 7.0);
    try std.testing.expectApproxEqAbs(@as(f64, 240.0), BP, 1e-12);
}

test "bollard at V = V_max is zero" {
    const BP = try bollardAtSpeedKN(240.0, 7.0, 7.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), BP, 1e-12);
}

test "bollard at V = V_max / 2 is BP_0 / 2" {
    const BP = try bollardAtSpeedKN(240.0, 3.5, 7.0);
    try std.testing.expectApproxEqAbs(@as(f64, 120.0), BP, 1e-12);
}

test "bollard above V_max is clamped to zero" {
    const BP = try bollardAtSpeedKN(240.0, 10.0, 7.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), BP, 1e-12);
}

test "bollard scales linearly with BP_0" {
    const BP1 = try bollardAtSpeedKN(100.0, 3.0, 7.0);
    const BP2 = try bollardAtSpeedKN(200.0, 3.0, 7.0);
    try std.testing.expectApproxEqAbs(2.0 * BP1, BP2, 1e-12);
}

test "verdict pass when effective exceeds required" {
    try std.testing.expectEqual(Verdict.pass, assistanceVerdict(150.0, 100.0));
}

test "verdict pass at exactly required" {
    try std.testing.expectEqual(Verdict.pass, assistanceVerdict(100.0, 100.0));
}

test "verdict fail when effective below required" {
    try std.testing.expectEqual(Verdict.fail, assistanceVerdict(80.0, 100.0));
}

test "input rejection: zero BP_0" {
    try std.testing.expectError(Error.NonPositiveBollard, bollardAtSpeedKN(0.0, 3.0, 7.0));
}

test "input rejection: negative V" {
    try std.testing.expectError(Error.InvalidSpeed, bollardAtSpeedKN(240.0, -1.0, 7.0));
}

test "input rejection: zero V_max" {
    try std.testing.expectError(Error.NonPositiveSpeed, bollardAtSpeedKN(240.0, 3.0, 0.0));
}
