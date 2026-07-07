const std = @import("std");

pub const Error = error{
    NonPositiveBollard,
    InvalidHeelAngle,
    InvalidTowlineAngle,
};

/// Indirect-towing (Reverse Arrest) effective tug force:
///   F_eff = BP * sin(beta) * cos(theta)
/// `beta_rad` is the tug heel angle [-pi/4, pi/4], `theta_rad` is
/// the tow-line angle to the assisted-ship axis [-pi/2, pi/2].
pub fn effectiveForceKN(
    BP_kN: f64,
    beta_rad: f64,
    theta_rad: f64,
) Error!f64 {
    if (!(BP_kN > 0)) return Error.NonPositiveBollard;
    if (!(beta_rad >= -std.math.pi / 4.0 and beta_rad <= std.math.pi / 4.0)) {
        return Error.InvalidHeelAngle;
    }
    if (!(theta_rad >= -std.math.pi / 2.0 and theta_rad <= std.math.pi / 2.0)) {
        return Error.InvalidTowlineAngle;
    }
    return BP_kN * @sin(beta_rad) * @cos(theta_rad);
}

/// Steering mode (tow-line angle theta drives the assisted ship's
/// yaw). The effective steering arm is the tow-line length L_line
/// times sin(theta).
pub fn steeringMomentKNm(
    F_eff_kN: f64,
    L_line_m: f64,
    theta_rad: f64,
) Error!f64 {
    if (!(L_line_m > 0)) return Error.NonPositiveBollard;
    if (!(theta_rad >= -std.math.pi / 2.0 and theta_rad <= std.math.pi / 2.0)) {
        return Error.InvalidTowlineAngle;
    }
    return F_eff_kN * L_line_m * @sin(theta_rad);
}

/// Braking mode (tow-line in-line with the assisted ship's stern).
/// The effective braking force equals F_eff at theta = 0:
///   F_brake = BP * sin(beta).
pub fn brakingForceKN(BP_kN: f64, beta_rad: f64) Error!f64 {
    return try effectiveForceKN(BP_kN, beta_rad, 0.0);
}

test "indirect force at beta = 30 deg, theta = 0 equals BP/2" {
    const F = try effectiveForceKN(200.0, std.math.pi / 6.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), F, 1e-9);
}

test "indirect force at beta = 0 is zero" {
    const F = try effectiveForceKN(200.0, 0.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), F, 1e-9);
}

test "indirect force at theta = pi/2 is zero" {
    const F = try effectiveForceKN(200.0, std.math.pi / 6.0, std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), F, 1e-9);
}

test "indirect force scales with BP" {
    const F1 = try effectiveForceKN(100.0, std.math.pi / 6.0, 0.2);
    const F2 = try effectiveForceKN(200.0, std.math.pi / 6.0, 0.2);
    try std.testing.expectApproxEqAbs(2.0 * F1, F2, 1e-9);
}

test "steering moment at F = 100 kN, L = 50 m, theta = pi/6 = 50 sin(pi/6)" {
    const M = try steeringMomentKNm(100.0, 50.0, std.math.pi / 6.0);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0 * 50.0 * 0.5), M, 1e-9);
}

test "steering moment zero at theta = 0" {
    const M = try steeringMomentKNm(100.0, 50.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), M, 1e-9);
}

test "braking force equals F_eff at theta = 0" {
    const F_b = try brakingForceKN(200.0, std.math.pi / 6.0);
    const F_e = try effectiveForceKN(200.0, std.math.pi / 6.0, 0.0);
    try std.testing.expectApproxEqAbs(F_e, F_b, 1e-12);
}

test "braking force at beta = 45 deg equals BP / sqrt(2)" {
    const F_b = try brakingForceKN(200.0, std.math.pi / 4.0);
    try std.testing.expectApproxEqAbs(200.0 / @sqrt(@as(f64, 2.0)), F_b, 1e-9);
}

test "input rejection: zero BP" {
    try std.testing.expectError(Error.NonPositiveBollard, effectiveForceKN(0.0, 0.5, 0.0));
}

test "input rejection: beta > pi/4" {
    try std.testing.expectError(
        Error.InvalidHeelAngle,
        effectiveForceKN(200.0, 1.0, 0.0),
    );
}

test "input rejection: theta > pi/2" {
    try std.testing.expectError(
        Error.InvalidTowlineAngle,
        effectiveForceKN(200.0, 0.5, 2.0),
    );
}
