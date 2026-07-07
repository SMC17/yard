const std = @import("std");

pub const Error = error{
    InvalidAngle,
    NegativeMoment,
    NonPositiveGZ,
};

/// Steady wind-heel angle phi_0 satisfies the static balance
/// `GZ(phi_0) = M_wind / Delta` where Delta is displacement and
/// M_wind = 0.5 rho_a C_D A V_wind^2 z_arm. The kernel exposes the
/// closed-form bisection inverse via `staticHeelAngleRad`.
///
/// In the simplified VL1 form for a wall-sided ship at small angles:
///   GZ(phi) = GM phi
/// giving phi_0 = M_wind / (Delta GM g) (small-angle linear regime).
pub fn staticHeelAngleSmallAngleRad(
    M_wind_nm: f64,
    Delta_kg: f64,
    GM_m: f64,
    g_mps2: f64,
) Error!f64 {
    if (!(M_wind_nm >= 0)) return Error.NegativeMoment;
    if (!(GM_m > 0)) return Error.NonPositiveGZ;
    if (!(Delta_kg > 0)) return Error.NonPositiveGZ;
    return M_wind_nm / (Delta_kg * GM_m * g_mps2);
}

/// VL1 residual roll envelope:
///   phi_1 = phi_0 + 1.7 phi_m
/// per MEPC.1/Circ.1627 Annex 3.
pub fn residualRollAngleRad(phi_0_rad: f64, phi_m_rad: f64) Error!f64 {
    if (!(phi_0_rad >= 0)) return Error.InvalidAngle;
    if (!(phi_m_rad >= 0)) return Error.InvalidAngle;
    return phi_0_rad + 1.7 * phi_m_rad;
}

pub const Verdict = enum {
    /// phi_1 < phi_F -- VL1 satisfied (low probability of dead-ship
    /// stability failure).
    pass,
    /// phi_1 >= phi_F -- VL1 not satisfied; second-tier check
    /// (Vulnerability Level 2 + direct simulation) required.
    fail,
};

pub fn verdict(phi_1_rad: f64, phi_F_rad: f64) Verdict {
    if (phi_1_rad < phi_F_rad) return .pass;
    return .fail;
}

test "small-angle heel: M=1e6, Delta=10000 kg, GM=0.6, g=9.81" {
    const phi = try staticHeelAngleSmallAngleRad(1.0e6, 10_000.0, 0.6, 9.81);
    // phi = 1e6 / (1e4 * 0.6 * 9.81) = 1e6 / 58860 = 16.99 rad. WAY too large.
    // Test that the linear formula is computed correctly; physical realism
    // requires Delta in proper units (mass).
    const expected = 1.0e6 / (10_000.0 * 0.6 * 9.81);
    try std.testing.expectApproxEqAbs(expected, phi, 1e-9);
}

test "heel scales linearly with wind moment" {
    const phi1 = try staticHeelAngleSmallAngleRad(1.0e5, 10_000_000.0, 0.6, 9.81);
    const phi2 = try staticHeelAngleSmallAngleRad(2.0e5, 10_000_000.0, 0.6, 9.81);
    try std.testing.expectApproxEqAbs(2.0 * phi1, phi2, 1e-12);
}

test "heel inversely proportional to GM" {
    const phi1 = try staticHeelAngleSmallAngleRad(1.0e5, 10_000_000.0, 1.0, 9.81);
    const phi2 = try staticHeelAngleSmallAngleRad(1.0e5, 10_000_000.0, 2.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), phi2 / phi1, 1e-12);
}

test "residualRoll: phi_1 = phi_0 + 1.7 phi_m" {
    const deg = std.math.pi / 180.0;
    const phi_1 = try residualRollAngleRad(5.0 * deg, 20.0 * deg);
    // 5 + 1.7 * 20 = 5 + 34 = 39 deg = 0.681 rad.
    const expected = 5.0 * deg + 1.7 * 20.0 * deg;
    try std.testing.expectApproxEqAbs(expected, phi_1, 1e-12);
}

test "verdict pass when phi_1 < phi_F" {
    const deg = std.math.pi / 180.0;
    try std.testing.expectEqual(Verdict.pass, verdict(35.0 * deg, 40.0 * deg));
}

test "verdict fail when phi_1 >= phi_F" {
    const deg = std.math.pi / 180.0;
    try std.testing.expectEqual(Verdict.fail, verdict(40.0 * deg, 40.0 * deg));
    try std.testing.expectEqual(Verdict.fail, verdict(45.0 * deg, 40.0 * deg));
}

test "input rejection: negative wind moment" {
    try std.testing.expectError(Error.NegativeMoment, staticHeelAngleSmallAngleRad(-1.0, 10_000.0, 0.6, 9.81));
}

test "input rejection: non-positive GM" {
    try std.testing.expectError(Error.NonPositiveGZ, staticHeelAngleSmallAngleRad(1.0e5, 10_000.0, 0.0, 9.81));
}

test "input rejection: negative phi_m" {
    try std.testing.expectError(Error.InvalidAngle, residualRollAngleRad(0.1, -0.1));
}
