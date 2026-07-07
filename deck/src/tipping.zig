const std = @import("std");

pub const Error = error{
    NonPositiveMoment,
    NonPositiveDisplacement,
    NonPositiveGM,
    InvalidAngle,
};

/// Static righting moment for a vessel at small heel angle phi:
///   M_R = Delta * g * GM * sin(phi).
pub fn rightingMomentNm(
    Delta_t: f64,
    GM_m: f64,
    phi_rad: f64,
    g_mps2: f64,
) Error!f64 {
    if (!(Delta_t > 0)) return Error.NonPositiveDisplacement;
    if (!(GM_m > 0)) return Error.NonPositiveGM;
    if (!(phi_rad >= 0 and phi_rad <= std.math.pi / 2.0)) return Error.InvalidAngle;
    return Delta_t * 1000.0 * g_mps2 * GM_m * @sin(phi_rad);
}

/// Equilibrium heel angle under a constant crane heeling moment:
///   sin(phi) = M_heel / (Delta g GM)
/// Returns the heel angle in radians; out-of-range (sin > 1) returns
/// an InvalidAngle error to flag overturning.
pub fn equilibriumHeelRad(
    M_heel_nm: f64,
    Delta_t: f64,
    GM_m: f64,
    g_mps2: f64,
) Error!f64 {
    if (!(M_heel_nm >= 0)) return Error.NonPositiveMoment;
    if (!(Delta_t > 0)) return Error.NonPositiveDisplacement;
    if (!(GM_m > 0)) return Error.NonPositiveGM;
    const s = M_heel_nm / (Delta_t * 1000.0 * g_mps2 * GM_m);
    if (s > 1.0) return Error.InvalidAngle;
    return std.math.asin(s);
}

pub const Verdict = enum {
    /// Equilibrium heel within the permissible limit.
    pass,
    /// Equilibrium heel exceeds permissible limit OR crane moment
    /// exceeds righting capacity.
    fail,
};

/// Tipping verdict: equilibrium heel < phi_max OR crane moment <
/// righting moment at phi_max.
pub fn tippingVerdict(
    M_heel_nm: f64,
    Delta_t: f64,
    GM_m: f64,
    phi_max_rad: f64,
    g_mps2: f64,
) Error!Verdict {
    if (!(phi_max_rad > 0 and phi_max_rad <= std.math.pi / 2.0)) return Error.InvalidAngle;
    const M_R_max = try rightingMomentNm(Delta_t, GM_m, phi_max_rad, g_mps2);
    if (M_heel_nm < M_R_max) return .pass;
    return .fail;
}

test "righting moment at phi = 0 is zero" {
    const M = try rightingMomentNm(10_000.0, 1.5, 0.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), M, 1e-12);
}

test "righting moment scales with sin(phi)" {
    const M_30 = try rightingMomentNm(10_000.0, 1.5, std.math.pi / 6.0, 9.81);
    const M_90 = try rightingMomentNm(10_000.0, 1.5, std.math.pi / 2.0, 9.81);
    try std.testing.expectApproxEqAbs(M_90, 2.0 * M_30, 1e-6);
}

test "righting moment at phi = 30 deg = Delta g GM * 0.5" {
    const M = try rightingMomentNm(10_000.0, 1.5, std.math.pi / 6.0, 9.81);
    const expected = 10_000.0 * 1000.0 * 9.81 * 1.5 * 0.5;
    try std.testing.expectApproxEqAbs(expected, M, 1e-3);
}

test "equilibrium heel at M_heel = 0 is zero" {
    const phi = try equilibriumHeelRad(0.0, 10_000.0, 1.5, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), phi, 1e-12);
}

test "equilibrium heel: M_heel = Delta g GM gives phi = pi/2" {
    const M_critical = 10_000.0 * 1000.0 * 9.81 * 1.5;
    const phi = try equilibriumHeelRad(M_critical, 10_000.0, 1.5, 9.81);
    try std.testing.expectApproxEqAbs(std.math.pi / 2.0, phi, 1e-9);
}

test "equilibrium heel: M_heel > Delta g GM returns InvalidAngle" {
    const M_critical = 10_000.0 * 1000.0 * 9.81 * 1.5;
    try std.testing.expectError(
        Error.InvalidAngle,
        equilibriumHeelRad(M_critical * 1.1, 10_000.0, 1.5, 9.81),
    );
}

test "tipping verdict pass when M_heel below righting at phi_max" {
    const v = try tippingVerdict(
        1.0e7, // small crane moment
        10_000.0,
        1.5,
        std.math.pi / 12.0, // 15 deg permissible
        9.81,
    );
    try std.testing.expectEqual(Verdict.pass, v);
}

test "tipping verdict fail when M_heel exceeds righting at phi_max" {
    const v = try tippingVerdict(
        1.0e9, // very large crane moment
        10_000.0,
        1.5,
        std.math.pi / 12.0,
        9.81,
    );
    try std.testing.expectEqual(Verdict.fail, v);
}

test "input rejection: zero GM" {
    try std.testing.expectError(
        Error.NonPositiveGM,
        equilibriumHeelRad(1.0e7, 10_000.0, 0.0, 9.81),
    );
}

test "input rejection: negative heeling moment" {
    try std.testing.expectError(
        Error.NonPositiveMoment,
        equilibriumHeelRad(-1.0, 10_000.0, 1.5, 9.81),
    );
}

test "input rejection: phi out of range" {
    try std.testing.expectError(
        Error.InvalidAngle,
        rightingMomentNm(10_000.0, 1.5, 2.0, 9.81),
    );
}
