const std = @import("std");

pub const Error = error{
    NonPositiveDensity,
    NonPositiveDiameter,
    NonPositiveRevs,
    NonPositiveArea,
    NonPositiveThrust,
    NonPositivePressure,
};

/// Velocity at 0.7 R per Burrill convention:
///   V_R = sqrt(V_a^2 + (0.7 pi n D)^2).
pub fn velocityAt07RMPerS(V_a_mps: f64, n_rps: f64, D_m: f64) Error!f64 {
    if (!(n_rps > 0)) return Error.NonPositiveRevs;
    if (!(D_m > 0)) return Error.NonPositiveDiameter;
    if (!(V_a_mps >= 0)) return Error.NonPositiveThrust;
    const v_rot = 0.7 * std.math.pi * n_rps * D_m;
    return @sqrt(V_a_mps * V_a_mps + v_rot * v_rot);
}

/// Local cavitation number based on 0.7 R velocity:
///   sigma_n = (p_0 - p_v) / (0.5 rho V_R^2).
pub fn localCavitationNumber(p0_pa: f64, pv_pa: f64, V_R_mps: f64, rho_kg_per_m3: f64) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(V_R_mps > 0)) return Error.NonPositiveRevs;
    if (!(p0_pa - pv_pa > 0)) return Error.NonPositivePressure;
    return (p0_pa - pv_pa) / (0.5 * rho_kg_per_m3 * V_R_mps * V_R_mps);
}

/// Burrill thrust-loading coefficient:
///   tau_c = T / (0.5 rho V_R^2 A_P)
/// where A_P is the projected blade area (not expanded).
pub fn thrustLoadingCoefficient(T_n: f64, V_R_mps: f64, AP_m2: f64, rho_kg_per_m3: f64) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(V_R_mps > 0)) return Error.NonPositiveRevs;
    if (!(AP_m2 > 0)) return Error.NonPositiveArea;
    if (!(T_n > 0)) return Error.NonPositiveThrust;
    return T_n / (0.5 * rho_kg_per_m3 * V_R_mps * V_R_mps * AP_m2);
}

/// Permissible Burrill thrust-loading coefficient for 5 % back-
/// cavitation per Burrill 1943 chart, parameterised as
///   tau_c_allow = a sigma_n^b
/// with a = 0.45, b = 0.4 (a least-squares fit to the published chart
/// for the merchant-propeller 5 percent back-cavitation contour valid
/// 0.2 <= sigma_n <= 2.0).
pub fn permissibleTauC5Pct(sigma_n: f64) Error!f64 {
    if (!(sigma_n > 0)) return Error.NonPositivePressure;
    return 0.45 * std.math.pow(f64, sigma_n, 0.4);
}

/// Permissible Burrill thrust-loading coefficient for 2.5 % back-
/// cavitation per Burrill 1943 chart, with a = 0.34, b = 0.4.
pub fn permissibleTauC2Pt5Pct(sigma_n: f64) Error!f64 {
    if (!(sigma_n > 0)) return Error.NonPositivePressure;
    return 0.34 * std.math.pow(f64, sigma_n, 0.4);
}

pub const Verdict = enum {
    /// tau_c < tau_c_allow at the chosen percentage: predicted safe.
    pass,
    /// tau_c >= tau_c_allow: predicted cavitating beyond the chosen
    /// back-cavitation percentage.
    fail,
};

/// Check a propeller operating point against the Burrill chart at the
/// 5 percent back-cavitation contour.
pub fn check5Pct(tau_c: f64, sigma_n: f64) Error!Verdict {
    const allow = try permissibleTauC5Pct(sigma_n);
    if (tau_c < allow) return .pass;
    return .fail;
}

test "V_R at zero advance: pure rotational at 0.7 R" {
    const V_R = try velocityAt07RMPerS(0.0, 10.0, 0.5);
    const expected = 0.7 * std.math.pi * 10.0 * 0.5;
    try std.testing.expectApproxEqAbs(expected, V_R, 1e-12);
}

test "V_R combines advance and rotation in quadrature" {
    const V_R = try velocityAt07RMPerS(5.0, 10.0, 0.5);
    const v_rot = 0.7 * std.math.pi * 10.0 * 0.5;
    try std.testing.expectApproxEqAbs(@sqrt(25.0 + v_rot * v_rot), V_R, 1e-12);
}

test "local cavitation number closed form" {
    const sigma = try localCavitationNumber(101325.0, 2300.0, 10.0, 1025.0);
    const expected = (101325.0 - 2300.0) / (0.5 * 1025.0 * 100.0);
    try std.testing.expectApproxEqAbs(expected, sigma, 1e-12);
}

test "thrust loading coefficient: doubling thrust doubles tau" {
    const t1 = try thrustLoadingCoefficient(100_000.0, 10.0, 1.5, 1025.0);
    const t2 = try thrustLoadingCoefficient(200_000.0, 10.0, 1.5, 1025.0);
    try std.testing.expectApproxEqAbs(2.0 * t1, t2, 1e-9);
}

test "permissible tau_c at sigma_n = 1: 5% chart returns 0.45" {
    const t = try permissibleTauC5Pct(1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.45), t, 1e-12);
}

test "permissible tau_c at sigma_n = 1: 2.5% chart returns 0.34" {
    const t = try permissibleTauC2Pt5Pct(1.0);
    std.debug.print("\n[VERIFICATION] Permissible Tau_C: {d}\n", .{t});
    try std.testing.expectApproxEqAbs(@as(f64, 0.34), t, 1e-12);
}

test "permissible tau_c at sigma_n = 4 follows power law" {
    const t = try permissibleTauC5Pct(4.0);
    // 0.45 * 4^0.4 = 0.45 * 1.74110 ~ 0.78350.
    try std.testing.expectApproxEqAbs(@as(f64, 0.45 * std.math.pow(f64, 4.0, 0.4)), t, 1e-12);
}

test "check5Pct: low loading at high sigma passes" {
    const v = try check5Pct(0.2, 2.0);
    try std.testing.expectEqual(Verdict.pass, v);
}

test "check5Pct: high loading at low sigma fails" {
    const v = try check5Pct(0.5, 0.2);
    try std.testing.expectEqual(Verdict.fail, v);
}

test "input rejection: non-positive thrust" {
    try std.testing.expectError(Error.NonPositiveThrust, thrustLoadingCoefficient(0.0, 10.0, 1.5, 1025.0));
}

test "input rejection: non-positive pressure differential" {
    try std.testing.expectError(Error.NonPositivePressure, localCavitationNumber(2000.0, 2300.0, 10.0, 1025.0));
}

test "input rejection: non-positive area" {
    try std.testing.expectError(Error.NonPositiveArea, thrustLoadingCoefficient(100_000.0, 10.0, 0.0, 1025.0));
}
