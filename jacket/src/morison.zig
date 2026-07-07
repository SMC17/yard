const std = @import("std");

pub const Error = error{
    NonPositiveDensity,
    NonPositiveDiameter,
    NonPositiveCoefficient,
    NonPositiveLength,
};

/// Morison force per unit length on a circular member, normal to its
/// axis, for the combined drag + inertia regime:
///   f = 0.5 rho C_D D u|u| + rho C_M (pi D^2 / 4) du/dt.
pub fn forcePerLengthNM(
    rho_kg_per_m3: f64,
    C_D: f64,
    C_M: f64,
    D_m: f64,
    u_mps: f64,
    du_dt_mps2: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(C_D > 0)) return Error.NonPositiveCoefficient;
    if (!(C_M > 0)) return Error.NonPositiveCoefficient;
    if (!(D_m > 0)) return Error.NonPositiveDiameter;
    const A = std.math.pi * D_m * D_m * 0.25;
    return 0.5 * rho_kg_per_m3 * C_D * D_m * u_mps * @abs(u_mps) +
        rho_kg_per_m3 * C_M * A * du_dt_mps2;
}

/// Integrate the Morison force over a vertical member of length L
/// assuming uniform u and du/dt along its length (a useful first-
/// order envelope for a chord or pile in a short wave).
pub fn forceUniformN(
    rho_kg_per_m3: f64,
    C_D: f64,
    C_M: f64,
    D_m: f64,
    u_mps: f64,
    du_dt_mps2: f64,
    L_m: f64,
) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    const f_per_m = try forcePerLengthNM(rho_kg_per_m3, C_D, C_M, D_m, u_mps, du_dt_mps2);
    return f_per_m * L_m;
}

/// Drag-only limit (large Keulegan-Carpenter number, KC > ~30):
///   f_D = 0.5 rho C_D D u|u|.
pub fn dragOnlyNM(rho: f64, C_D: f64, D: f64, u: f64) Error!f64 {
    return try forcePerLengthNM(rho, C_D, 1.0, D, u, 0.0);
}

/// Inertia-only limit (small Keulegan-Carpenter number, KC < ~3):
///   f_I = rho C_M (pi D^2 / 4) du/dt.
pub fn inertiaOnlyNM(rho: f64, C_M: f64, D: f64, du_dt: f64) Error!f64 {
    return try forcePerLengthNM(rho, 1.0, C_M, D, 0.0, du_dt);
}

test "force per length combines drag and inertia" {
    // rho=1025, C_D=1.0, C_M=2.0, D=1.0, u=2, du/dt=1.
    // f_D = 0.5 * 1025 * 1.0 * 1.0 * 2 * 2 = 2050.
    // A = pi/4 = 0.7854, f_I = 1025 * 2.0 * 0.7854 * 1 = 1610.
    // total = 3660.
    const f = try forcePerLengthNM(1025.0, 1.0, 2.0, 1.0, 2.0, 1.0);
    const expected = 0.5 * 1025.0 * 1.0 * 1.0 * 4.0 + 1025.0 * 2.0 * std.math.pi * 0.25 * 1.0;
    try std.testing.expectApproxEqAbs(expected, f, 1e-9);
}

test "uniform force integrates over length" {
    const f_per = try forcePerLengthNM(1025.0, 1.0, 2.0, 1.0, 2.0, 1.0);
    const F = try forceUniformN(1025.0, 1.0, 2.0, 1.0, 2.0, 1.0, 10.0);
    try std.testing.expectApproxEqAbs(f_per * 10.0, F, 1e-9);
}

test "drag-only limit: inertia term vanishes when du_dt = 0" {
    const f = try dragOnlyNM(1025.0, 1.0, 1.0, 2.0);
    // 0.5 * 1025 * 1 * 1 * 4 = 2050.
    try std.testing.expectApproxEqAbs(@as(f64, 2050.0), f, 1e-9);
}

test "inertia-only limit: drag term vanishes when u = 0" {
    const f = try inertiaOnlyNM(1025.0, 2.0, 1.0, 1.0);
    // rho C_M pi D^2 / 4 = 1025 * 2 * pi / 4 = 1610.05.
    const expected = 1025.0 * 2.0 * std.math.pi * 0.25;
    try std.testing.expectApproxEqAbs(expected, f, 1e-9);
}

test "drag preserves sign via u|u|" {
    const f_pos = try dragOnlyNM(1025.0, 1.0, 1.0, 2.0);
    const f_neg = try dragOnlyNM(1025.0, 1.0, 1.0, -2.0);
    try std.testing.expectApproxEqAbs(f_pos, -f_neg, 1e-9);
}

test "inertia scales linearly with du_dt" {
    const f1 = try inertiaOnlyNM(1025.0, 2.0, 1.0, 1.0);
    const f2 = try inertiaOnlyNM(1025.0, 2.0, 1.0, 2.0);
    try std.testing.expectApproxEqAbs(2.0 * f1, f2, 1e-9);
}

test "drag scales quadratically with u" {
    const f1 = try dragOnlyNM(1025.0, 1.0, 1.0, 1.0);
    const f2 = try dragOnlyNM(1025.0, 1.0, 1.0, 2.0);
    try std.testing.expectApproxEqAbs(4.0 * f1, f2, 1e-9);
}

test "force per length scales with D^2 in inertia term" {
    const f1 = try inertiaOnlyNM(1025.0, 2.0, 1.0, 1.0);
    const f2 = try inertiaOnlyNM(1025.0, 2.0, 2.0, 1.0);
    try std.testing.expectApproxEqAbs(4.0 * f1, f2, 1e-9);
}

test "input rejection: zero density" {
    try std.testing.expectError(Error.NonPositiveDensity, forcePerLengthNM(0.0, 1.0, 2.0, 1.0, 2.0, 1.0));
}

test "input rejection: zero length" {
    try std.testing.expectError(Error.NonPositiveLength, forceUniformN(1025.0, 1.0, 2.0, 1.0, 2.0, 1.0, 0.0));
}
