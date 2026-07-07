const std = @import("std");

pub const Error = error{
    NonPositiveSpan,
    NonPositiveArea,
    NonPositiveSpeed,
    NonPositiveDensity,
    InvalidAngleOfAttack,
};

/// Effective aspect ratio for a surface-piercing keel:
///   AR_eff = h^2 / S
/// where `h` is the geometric depth below the waterline (the free
/// surface acts as a mirror, doubling the geometric span). Caller
/// passes the geometric h and the planform area S.
pub fn effectiveAspectRatio(h_m: f64, S_m2: f64) Error!f64 {
    if (!(h_m > 0)) return Error.NonPositiveSpan;
    if (!(S_m2 > 0)) return Error.NonPositiveArea;
    return h_m * h_m / S_m2;
}

/// Lift coefficient per the lifting-line approximation:
///   C_L = 2 pi alpha AR / (AR + 2).
/// `alpha_rad` is the small-angle leeway / rudder angle in radians.
pub fn liftCoefficient(alpha_rad: f64, AR: f64) Error!f64 {
    if (!(AR > 0)) return Error.NonPositiveArea;
    if (!(@abs(alpha_rad) < std.math.pi / 2.0)) return Error.InvalidAngleOfAttack;
    return 2.0 * std.math.pi * alpha_rad * AR / (AR + 2.0);
}

/// Induced-drag coefficient:
///   C_Di = C_L^2 / (pi AR).
pub fn inducedDragCoefficient(C_L: f64, AR: f64) Error!f64 {
    if (!(AR > 0)) return Error.NonPositiveArea;
    return C_L * C_L / (std.math.pi * AR);
}

/// Side force F_side = 0.5 rho V^2 S C_L [N].
pub fn sideForceN(
    rho_kg_per_m3: f64,
    V_mps: f64,
    S_m2: f64,
    C_L: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(S_m2 > 0)) return Error.NonPositiveArea;
    return 0.5 * rho_kg_per_m3 * V_mps * V_mps * S_m2 * C_L;
}

/// Induced drag force D_i = 0.5 rho V^2 S C_Di [N].
pub fn inducedDragN(
    rho_kg_per_m3: f64,
    V_mps: f64,
    S_m2: f64,
    C_Di: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(S_m2 > 0)) return Error.NonPositiveArea;
    return 0.5 * rho_kg_per_m3 * V_mps * V_mps * S_m2 * C_Di;
}

test "AR for h = 2 m, S = 1 m^2 is 4" {
    const AR = try effectiveAspectRatio(2.0, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), AR, 1e-12);
}

test "lift coefficient at alpha = 5 deg, AR = 4" {
    // C_L = 2 pi * 5*pi/180 * 4 / 6 = (5*pi^2 / 90) * 4/6 ~ 0.3654.
    const alpha = 5.0 * std.math.pi / 180.0;
    const C_L = try liftCoefficient(alpha, 4.0);
    const expected = 2.0 * std.math.pi * alpha * 4.0 / 6.0;
    try std.testing.expectApproxEqAbs(expected, C_L, 1e-12);
}

test "lift slope dC_L/dalpha = 2 pi AR / (AR + 2)" {
    const AR: f64 = 4.0;
    const alpha_1 = 0.05;
    const alpha_2 = 0.10;
    const C_L_1 = try liftCoefficient(alpha_1, AR);
    const C_L_2 = try liftCoefficient(alpha_2, AR);
    const slope = (C_L_2 - C_L_1) / (alpha_2 - alpha_1);
    const expected = 2.0 * std.math.pi * AR / (AR + 2.0);
    try std.testing.expectApproxEqAbs(expected, slope, 1e-12);
}

test "high-AR limit approaches 2D thin-airfoil slope 2 pi" {
    const C_L_high = try liftCoefficient(0.05, 1.0e6);
    const C_L_lifting_line_max = 2.0 * std.math.pi * 0.05;
    // High AR: AR / (AR + 2) -> 1, so slope -> 2 pi.
    try std.testing.expectApproxEqAbs(C_L_lifting_line_max, C_L_high, 1e-6);
}

test "low-AR limit gives small lift" {
    const C_L_high = try liftCoefficient(0.05, 100.0);
    const C_L_low = try liftCoefficient(0.05, 0.5);
    try std.testing.expect(C_L_low < C_L_high);
}

test "induced drag scales with C_L^2" {
    const AR: f64 = 4.0;
    const CDi_1 = try inducedDragCoefficient(0.1, AR);
    const CDi_2 = try inducedDragCoefficient(0.2, AR);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), CDi_2 / CDi_1, 1e-12);
}

test "induced drag at AR = pi: C_Di = C_L^2 / pi^2" {
    const CDi = try inducedDragCoefficient(0.3, std.math.pi);
    const expected = 0.09 / (std.math.pi * std.math.pi);
    try std.testing.expectApproxEqAbs(expected, CDi, 1e-12);
}

test "side force scales with V^2" {
    const F1 = try sideForceN(1025.0, 5.0, 2.0, 0.3);
    const F2 = try sideForceN(1025.0, 10.0, 2.0, 0.3);
    try std.testing.expectApproxEqAbs(4.0 * F1, F2, 1e-9);
}

test "induced drag much smaller than side force at small alpha" {
    const AR: f64 = 4.0;
    const alpha = 0.05;
    const C_L = try liftCoefficient(alpha, AR);
    const C_Di = try inducedDragCoefficient(C_L, AR);
    const ratio = C_Di / C_L;
    // ratio ~ C_L / (pi AR) ~ 0.0124 / (pi * 4) ~ 0.001 at small alpha.
    try std.testing.expect(ratio < 0.1);
}

test "input rejection: zero AR" {
    try std.testing.expectError(Error.NonPositiveArea, liftCoefficient(0.1, 0.0));
}

test "input rejection: alpha >= pi/2" {
    try std.testing.expectError(Error.InvalidAngleOfAttack, liftCoefficient(std.math.pi / 2.0, 4.0));
}

test "input rejection: zero speed" {
    try std.testing.expectError(Error.NonPositiveSpeed, sideForceN(1025.0, 0.0, 1.0, 0.3));
}
