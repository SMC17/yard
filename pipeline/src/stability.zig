const std = @import("std");

pub const Error = error{
    NonPositiveDensity,
    NonPositiveDiameter,
    NonPositiveFriction,
    NegativeVelocity,
    NonPositiveCoefficient,
};

/// Morison-equation drag force per unit length:
///   F_D = 0.5 rho C_D D U|U|.
pub fn dragForcePerLengthNM(
    rho_kg_per_m3: f64,
    C_D: f64,
    D_m: f64,
    U_mps: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(C_D > 0)) return Error.NonPositiveCoefficient;
    if (!(D_m > 0)) return Error.NonPositiveDiameter;
    return 0.5 * rho_kg_per_m3 * C_D * D_m * U_mps * @abs(U_mps);
}

/// Morison-equation inertia force per unit length:
///   F_I = rho C_M (pi D^2 / 4) (dU/dt).
pub fn inertiaForcePerLengthNM(
    rho_kg_per_m3: f64,
    C_M: f64,
    D_m: f64,
    dU_dt_mps2: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(C_M > 0)) return Error.NonPositiveCoefficient;
    if (!(D_m > 0)) return Error.NonPositiveDiameter;
    return rho_kg_per_m3 * C_M * std.math.pi * D_m * D_m * 0.25 * dU_dt_mps2;
}

/// Morison-equation lift force per unit length:
///   F_L = 0.5 rho C_L D U^2.
pub fn liftForcePerLengthNM(
    rho_kg_per_m3: f64,
    C_L: f64,
    D_m: f64,
    U_mps: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(C_L > 0)) return Error.NonPositiveCoefficient;
    if (!(D_m > 0)) return Error.NonPositiveDiameter;
    return 0.5 * rho_kg_per_m3 * C_L * D_m * U_mps * U_mps;
}

/// DNV-RP-F109 simplified lateral-stability criterion. Required
/// submerged weight per unit length is:
///   W_s_req = (F_D + F_I) * SF / mu_friction + F_L
/// where SF is the lateral-stability safety factor (typ. 1.1 for
/// stable category, 1.4 for absolute lateral static stability).
pub fn requiredSubmergedWeightNM(
    F_D: f64,
    F_I: f64,
    F_L: f64,
    mu_friction: f64,
    safety_factor: f64,
) Error!f64 {
    if (!(mu_friction > 0)) return Error.NonPositiveFriction;
    if (!(safety_factor > 0)) return Error.NonPositiveFriction;
    return (F_D + F_I) * safety_factor / mu_friction + F_L;
}

pub const Verdict = enum {
    /// Actual submerged weight >= required -- pipeline is stable.
    pass,
    /// Actual submerged weight < required -- additional concrete
    /// coating, trenching, or rock dumping required.
    fail,
};

pub fn verdict(W_s_actual: f64, W_s_required: f64) Verdict {
    if (W_s_actual >= W_s_required) return .pass;
    return .fail;
}

test "drag force per length closed form" {
    // F_D = 0.5 * 1025 * 1.2 * 0.5 * 2 * 2 = 1230 N/m.
    const F = try dragForcePerLengthNM(1025.0, 1.2, 0.5, 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1230.0), F, 1e-9);
}

test "drag force preserves direction sign via U|U|" {
    const F_pos = try dragForcePerLengthNM(1025.0, 1.2, 0.5, 2.0);
    const F_neg = try dragForcePerLengthNM(1025.0, 1.2, 0.5, -2.0);
    try std.testing.expectApproxEqAbs(F_pos, -F_neg, 1e-9);
}

test "inertia force per length: rho C_M (pi D^2 / 4) du/dt" {
    // F_I = 1025 * 2.0 * (pi * 0.25 / 4) * 1.0 = 1025 * 2 * 0.19635 * 1.0
    //     = 1025 * 0.39270 = 402.51 N/m.
    const F = try inertiaForcePerLengthNM(1025.0, 2.0, 0.5, 1.0);
    const expected = 1025.0 * 2.0 * std.math.pi * 0.25 * 0.25 * 1.0;
    try std.testing.expectApproxEqAbs(expected, F, 1e-9);
}

test "lift force per length: 0.5 rho C_L D U^2" {
    // F_L = 0.5 * 1025 * 0.9 * 0.5 * 4 = 922.5 N/m.
    const F = try liftForcePerLengthNM(1025.0, 0.9, 0.5, 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 922.5), F, 1e-9);
}

test "required submerged weight closed form" {
    // F_D = 1230, F_I = 0, F_L = 922.5, mu = 0.5, SF = 1.1.
    // W = (1230 + 0) * 1.1 / 0.5 + 922.5 = 2706 + 922.5 = 3628.5 N/m.
    const W = try requiredSubmergedWeightNM(1230.0, 0.0, 922.5, 0.5, 1.1);
    try std.testing.expectApproxEqAbs(@as(f64, 3628.5), W, 1e-9);
}

test "required weight scales linearly in safety factor (drag term)" {
    const W1 = try requiredSubmergedWeightNM(600.0, 100.0, 0.0, 0.5, 1.0);
    const W2 = try requiredSubmergedWeightNM(600.0, 100.0, 0.0, 0.5, 2.0);
    try std.testing.expectApproxEqAbs(2.0 * W1, W2, 1e-9);
}

test "required weight inversely proportional to friction (drag term)" {
    const W1 = try requiredSubmergedWeightNM(600.0, 100.0, 0.0, 0.4, 1.0);
    const W2 = try requiredSubmergedWeightNM(600.0, 100.0, 0.0, 0.8, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), W2 / W1, 1e-9);
}

test "verdict pass at exactly required weight" {
    try std.testing.expectEqual(Verdict.pass, verdict(3628.5, 3628.5));
}

test "verdict fail when actual < required" {
    try std.testing.expectEqual(Verdict.fail, verdict(2000.0, 3628.5));
}

test "input rejection: non-positive density" {
    try std.testing.expectError(Error.NonPositiveDensity, dragForcePerLengthNM(0.0, 1.2, 0.5, 2.0));
}

test "input rejection: zero coefficient" {
    try std.testing.expectError(Error.NonPositiveCoefficient, dragForcePerLengthNM(1025.0, 0.0, 0.5, 2.0));
}

test "input rejection: zero friction" {
    try std.testing.expectError(Error.NonPositiveFriction, requiredSubmergedWeightNM(600.0, 0.0, 0.0, 0.0, 1.1));
}
