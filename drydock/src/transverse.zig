const std = @import("std");

pub const Error = error{
    NonPositiveBuoyancy,
    NonPositiveDimension,
    NonPositiveGM,
};

/// Loss of metacentric height due to a virtual rise of CG as the
/// ship sits on the keel blocks:
///   GG_v = P l / Delta
/// where P is the upward block force (= W - B at the partially
/// docked condition), l is the lever arm from K to G, and Delta is
/// the residual buoyancy displacement.
///
/// (Watson 1998 / Tupper 2013 docking-stability convention.)
pub fn virtualGGRiseM(
    P_n: f64,
    KG_m: f64,
    Delta_n: f64,
) Error!f64 {
    if (!(P_n >= 0)) return Error.NonPositiveBuoyancy;
    if (!(KG_m >= 0)) return Error.NonPositiveDimension;
    if (!(Delta_n > 0)) return Error.NonPositiveBuoyancy;
    return P_n * KG_m / Delta_n;
}

/// Residual metacentric height during docking:
///   GM_residual = GM_initial - GG_v.
pub fn residualGMM(
    GM_initial_m: f64,
    GG_v_m: f64,
) Error!f64 {
    if (!(GM_initial_m > 0)) return Error.NonPositiveGM;
    if (!(GG_v_m >= 0)) return Error.NonPositiveDimension;
    return GM_initial_m - GG_v_m;
}

pub const Verdict = enum {
    /// GM_residual > 0: ship stable on the blocks.
    pass,
    /// GM_residual <= 0: ship unstable; can heel and fall over.
    fail,
};

/// Docking-stability verdict.
pub fn dockingStabilityVerdict(GM_residual_m: f64) Verdict {
    if (GM_residual_m > 0) return .pass;
    return .fail;
}

/// Block-force at the time the ship just settles on the keel
/// blocks (water still draining):
///   P_critical = W - B_residual
/// where B_residual is the buoyancy at the residual draft.
pub fn criticalBlockForceN(W_n: f64, B_residual_n: f64) Error!f64 {
    if (!(W_n > 0)) return Error.NonPositiveBuoyancy;
    if (!(B_residual_n >= 0)) return Error.NonPositiveBuoyancy;
    if (B_residual_n > W_n) return 0.0;
    return W_n - B_residual_n;
}

test "virtual GG rise: P = 1 MN, KG = 5 m, Delta = 100 MN = 0.05 m" {
    const GG = try virtualGGRiseM(1.0e6, 5.0, 100.0e6);
    try std.testing.expectApproxEqAbs(@as(f64, 0.05), GG, 1e-9);
}

test "virtual GG rise scales linearly with P" {
    const GG1 = try virtualGGRiseM(1.0e6, 5.0, 100.0e6);
    const GG2 = try virtualGGRiseM(2.0e6, 5.0, 100.0e6);
    try std.testing.expectApproxEqAbs(2.0 * GG1, GG2, 1e-9);
}

test "virtual GG rise inversely proportional to Delta" {
    const GG1 = try virtualGGRiseM(1.0e6, 5.0, 100.0e6);
    const GG2 = try virtualGGRiseM(1.0e6, 5.0, 200.0e6);
    try std.testing.expectApproxEqAbs(0.5 * GG1, GG2, 1e-9);
}

test "residual GM: 1.5 m initial - 0.4 m GG = 1.1 m" {
    const GM = try residualGMM(1.5, 0.4);
    try std.testing.expectApproxEqAbs(@as(f64, 1.1), GM, 1e-12);
}

test "residual GM can become negative" {
    const GM = try residualGMM(1.5, 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, -0.5), GM, 1e-12);
}

test "docking stability pass when GM positive" {
    try std.testing.expectEqual(Verdict.pass, dockingStabilityVerdict(0.5));
}

test "docking stability fail when GM is zero" {
    try std.testing.expectEqual(Verdict.fail, dockingStabilityVerdict(0.0));
}

test "docking stability fail when GM negative" {
    try std.testing.expectEqual(Verdict.fail, dockingStabilityVerdict(-0.2));
}

test "critical block force: 100 MN W - 60 MN B = 40 MN" {
    const P = try criticalBlockForceN(100.0e6, 60.0e6);
    try std.testing.expectApproxEqAbs(@as(f64, 40.0e6), P, 1e-6);
}

test "critical block force clamps to zero when B > W" {
    const P = try criticalBlockForceN(100.0e6, 110.0e6);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), P, 1e-12);
}

test "critical block force at B = 0 equals W" {
    const P = try criticalBlockForceN(50.0e6, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0e6), P, 1e-12);
}

test "input rejection: zero Delta" {
    try std.testing.expectError(Error.NonPositiveBuoyancy, virtualGGRiseM(1.0e6, 5.0, 0.0));
}

test "input rejection: negative GM" {
    try std.testing.expectError(Error.NonPositiveGM, residualGMM(-0.5, 0.4));
}
