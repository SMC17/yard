const std = @import("std");

pub const Error = error{
    NonPositiveHeight,
    NonPositiveGM,
    NonPositiveDisplacement,
    InvalidHeelAngle,
};

/// Approach velocity at water-contact for a ship tipped sideways off
/// a slipway of height H:
///   v = sqrt(2 g H).
pub fn waterContactVelocityMPerS(H_m: f64, g_mps2: f64) Error!f64 {
    if (!(H_m > 0)) return Error.NonPositiveHeight;
    return @sqrt(2.0 * g_mps2 * H_m);
}

/// Maximum heel angle on water-impact for a side-launched ship
/// of metacentric height GM and approach kinetic energy E_k:
///   0.5 m v^2 = (1/2) Delta g GM phi_max^2  (linear stiffness)
///   phi_max = sqrt(v^2 / (g GM))
/// (small-angle assumption; for large heel the GZ curve must be
/// integrated numerically).
pub fn maximumHeelAngleRad(
    v_mps: f64,
    GM_m: f64,
    g_mps2: f64,
) Error!f64 {
    if (!(GM_m > 0)) return Error.NonPositiveGM;
    if (!(v_mps >= 0)) return Error.NonPositiveHeight;
    return @sqrt(v_mps * v_mps / (g_mps2 * GM_m));
}

/// Composer: side-launch maximum heel from slipway height + GM.
pub fn maxHeelFromSlipway(
    H_m: f64,
    GM_m: f64,
    g_mps2: f64,
) Error!f64 {
    const v = try waterContactVelocityMPerS(H_m, g_mps2);
    return try maximumHeelAngleRad(v, GM_m, g_mps2);
}

pub const Verdict = enum {
    /// Maximum heel below the deck-edge immersion / downflooding angle.
    pass,
    /// Maximum heel reaches or exceeds the deck-edge angle.
    fail,
};

pub fn heelVerdict(phi_max_rad: f64, phi_deck_edge_rad: f64) Error!Verdict {
    if (!(phi_max_rad >= 0)) return Error.InvalidHeelAngle;
    if (!(phi_deck_edge_rad > 0)) return Error.InvalidHeelAngle;
    if (phi_max_rad < phi_deck_edge_rad) return .pass;
    return .fail;
}

test "water-contact velocity at H = 5 m" {
    const v = try waterContactVelocityMPerS(5.0, 9.81);
    const expected = @sqrt(2.0 * 9.81 * 5.0);
    try std.testing.expectApproxEqAbs(expected, v, 1e-9);
    // ~ 9.9 m/s.
    try std.testing.expect(v > 9.5 and v < 10.5);
}

test "water-contact velocity scales with sqrt(H)" {
    const v1 = try waterContactVelocityMPerS(2.0, 9.81);
    const v2 = try waterContactVelocityMPerS(8.0, 9.81);
    try std.testing.expectApproxEqAbs(2.0 * v1, v2, 1e-9);
}

test "max heel at v = 5, GM = 1.5, g = 9.81" {
    const phi = try maximumHeelAngleRad(5.0, 1.5, 9.81);
    const expected = @sqrt(25.0 / (9.81 * 1.5));
    try std.testing.expectApproxEqAbs(expected, phi, 1e-9);
    // 5 / sqrt(14.715) = 5 / 3.836 = 1.303 rad = 74.7 deg.
    // (Beyond linear-stiffness assumption, but illustrates the kernel.)
    try std.testing.expect(phi > 0.0);
}

test "max heel inversely proportional to sqrt(GM)" {
    const phi1 = try maximumHeelAngleRad(3.0, 1.0, 9.81);
    const phi2 = try maximumHeelAngleRad(3.0, 4.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), phi2 / phi1, 1e-9);
}

test "max heel proportional to v" {
    const phi1 = try maximumHeelAngleRad(2.0, 1.5, 9.81);
    const phi2 = try maximumHeelAngleRad(4.0, 1.5, 9.81);
    try std.testing.expectApproxEqAbs(2.0 * phi1, phi2, 1e-9);
}

test "composer reproduces phi from H, GM" {
    const phi = try maxHeelFromSlipway(2.0, 1.5, 9.81);
    const v = try waterContactVelocityMPerS(2.0, 9.81);
    const phi_expected = try maximumHeelAngleRad(v, 1.5, 9.81);
    try std.testing.expectApproxEqAbs(phi_expected, phi, 1e-12);
}

test "verdict pass when phi_max < phi_deck_edge" {
    const v = try heelVerdict(0.3, 0.5);
    try std.testing.expectEqual(Verdict.pass, v);
}

test "verdict fail when phi_max >= phi_deck_edge" {
    const v = try heelVerdict(0.5, 0.5);
    try std.testing.expectEqual(Verdict.fail, v);
}

test "verdict fail when phi_max well over deck edge" {
    const v = try heelVerdict(0.8, 0.5);
    try std.testing.expectEqual(Verdict.fail, v);
}

test "input rejection: zero H" {
    try std.testing.expectError(Error.NonPositiveHeight, waterContactVelocityMPerS(0.0, 9.81));
}

test "input rejection: zero GM" {
    try std.testing.expectError(Error.NonPositiveGM, maximumHeelAngleRad(5.0, 0.0, 9.81));
}

test "input rejection: zero deck-edge angle" {
    try std.testing.expectError(Error.InvalidHeelAngle, heelVerdict(0.3, 0.0));
}
