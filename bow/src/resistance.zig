const std = @import("std");
const area_mod = @import("area.zig");

pub const Error = error{
    NonPositiveSpeed,
    NonPositiveArea,
    NonPositiveDensity,
    InvalidGeometry,
};

/// Holtrop-Mennen 1984 additional resistance term for the bulbous
/// bow:
///   R_B = 0.11 exp(-3 P_B^(-2)) Fn_i^3 A_BT^1.5 rho g / (1 + Fn_i^2)
/// Returns the per-component resistance contribution in N. Caller
/// supplies the bulb-tip Froude number Fn_i (typically from
/// `area.bulbFroudeNumber`) and the immersion factor P_B (from
/// `area.immersionFactorPB`).
pub fn bulbResistanceN(
    P_B: f64,
    Fn_i: f64,
    A_BT_m2: f64,
    rho_kg_per_m3: f64,
    g_mps2: f64,
) Error!f64 {
    if (!(Fn_i > 0)) return Error.NonPositiveSpeed;
    if (!(A_BT_m2 > 0)) return Error.NonPositiveArea;
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(P_B > 0)) return Error.InvalidGeometry;
    const decay = @exp(-3.0 / (P_B * P_B));
    const denom = 1.0 + Fn_i * Fn_i;
    return 0.11 * decay * std.math.pow(f64, Fn_i, 3) *
        std.math.pow(f64, A_BT_m2, 1.5) * rho_kg_per_m3 * g_mps2 / denom;
}

/// Single-step composer: take the bulb geometry + ship speed +
/// fluid density and produce R_B directly.
pub fn bulbResistanceFromGeometry(
    A_BT_m2: f64,
    T_F_m: f64,
    h_B_m: f64,
    V_mps: f64,
    rho_kg_per_m3: f64,
    g_mps2: f64,
) Error!f64 {
    const P_B = area_mod.immersionFactorPB(A_BT_m2, T_F_m, h_B_m) catch return Error.InvalidGeometry;
    const Fn_i = area_mod.bulbFroudeNumber(V_mps, A_BT_m2, T_F_m, h_B_m, g_mps2) catch return Error.InvalidGeometry;
    return try bulbResistanceN(P_B, Fn_i, A_BT_m2, rho_kg_per_m3, g_mps2);
}

/// Ratio of bulb resistance to a reference wave resistance R_W
/// (caller computes R_W via the Holtrop wave-resistance regression
/// in `yard-resistance-zig`). A negative ratio indicates that the
/// bulb reduces the bare-hull wave resistance more than R_B adds.
pub fn bulbResistanceRatio(R_B_n: f64, R_W_n: f64) Error!f64 {
    if (!(@abs(R_W_n) > 1e-9)) return Error.NonPositiveSpeed;
    return R_B_n / R_W_n;
}

test "R_B at typical Aframax bulb" {
    // A_BT=10 m^2, T_F=15 m, h_B=5 m, V=8 m/s, rho=1025.
    // P_B = 0.56 * sqrt(10) / (15 - 7.5) = 0.56 * 3.162 / 7.5 = 0.2361
    // Fn_i = 8 / sqrt(9.81 * (15 - 5 - 0.79) + 0.15 * 64) = 8 / sqrt(99.96) = 0.800
    // decay = exp(-3 / 0.05576) = exp(-53.8) ~ 4e-24 (very small)
    // R_B is therefore very small for this configuration.
    const R_B = try bulbResistanceFromGeometry(10.0, 15.0, 5.0, 8.0, 1025.0, 9.81);
    try std.testing.expect(R_B >= 0.0);
    try std.testing.expect(std.math.isFinite(R_B));
}

test "R_B scales with A_BT^1.5 at fixed Fn_i, P_B" {
    const R1 = try bulbResistanceN(0.5, 0.5, 4.0, 1025.0, 9.81);
    const R2 = try bulbResistanceN(0.5, 0.5, 16.0, 1025.0, 9.81);
    const ratio = std.math.pow(f64, 4.0, 1.5);
    try std.testing.expectApproxEqAbs(ratio * R1, R2, 1e-6);
}

test "R_B scales with Fn_i^3 / (1 + Fn_i^2) at fixed P_B, A_BT" {
    const R1 = try bulbResistanceN(1.0, 0.5, 4.0, 1025.0, 9.81);
    const R2 = try bulbResistanceN(1.0, 1.0, 4.0, 1025.0, 9.81);
    // Ratio = (1^3 / 2) / (0.125 / 1.25) = 0.5 / 0.1 = 5.
    try std.testing.expectApproxEqAbs(5.0 * R1, R2, 1e-6);
}

test "R_B decay factor: P_B large (deep bulb) gives exp(-3/P_B^2) -> 1" {
    const R_big = try bulbResistanceN(100.0, 0.5, 4.0, 1025.0, 9.81);
    const R_unit = 0.11 * 1.0 * std.math.pow(f64, @as(f64, 0.5), 3) *
        std.math.pow(f64, @as(f64, 4.0), 1.5) * 1025.0 * 9.81 / (1.0 + 0.25);
    try std.testing.expectApproxEqAbs(R_unit, R_big, R_unit * 1e-3);
}

test "R_B decay factor at P_B = 1: exp(-3) = 0.0498" {
    const R = try bulbResistanceN(1.0, 0.5, 4.0, 1025.0, 9.81);
    const decay = @exp(@as(f64, -3.0));
    const expected = 0.11 * decay * std.math.pow(f64, @as(f64, 0.5), 3) *
        std.math.pow(f64, @as(f64, 4.0), 1.5) * 1025.0 * 9.81 / 1.25;
    try std.testing.expectApproxEqAbs(expected, R, 1e-6);
}

test "R_B scales linearly with rho * g" {
    const R1 = try bulbResistanceN(1.0, 0.5, 4.0, 1025.0, 9.81);
    const R2 = try bulbResistanceN(1.0, 0.5, 4.0, 2050.0, 9.81);
    try std.testing.expectApproxEqAbs(2.0 * R1, R2, 1e-6);
}

test "bulb resistance ratio: R_B / R_W = 0.1 at R_B = 1000, R_W = 10000" {
    const r = try bulbResistanceRatio(1000.0, 10_000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), r, 1e-12);
}

test "input rejection: non-positive Fn_i" {
    try std.testing.expectError(Error.NonPositiveSpeed, bulbResistanceN(1.0, 0.0, 4.0, 1025.0, 9.81));
}

test "input rejection: non-positive density" {
    try std.testing.expectError(Error.NonPositiveDensity, bulbResistanceN(1.0, 0.5, 4.0, 0.0, 9.81));
}

test "composer rejects degenerate geometry" {
    try std.testing.expectError(
        Error.InvalidGeometry,
        bulbResistanceFromGeometry(10.0, 5.0, 4.0, 8.0, 1025.0, 9.81),
    );
}
