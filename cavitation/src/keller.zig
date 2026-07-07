const std = @import("std");

pub const Error = error{
    NonPositivePressure,
    NonPositiveThrust,
    NonPositiveDiameter,
    InvalidBladeCount,
};

/// Single-screw vessel constant K for Keller's formula. Per Keller 1973
/// merchant-ship single-screw: K = 0.20. Twin-screw: K = 0.00.
pub const k_single_screw: f64 = 0.20;
pub const k_twin_screw: f64 = 0.00;

/// Minimum expanded blade-area ratio per Keller 1973:
///   A_E / A_0 >= (1.3 + 0.3 Z) T / ((p_0 - p_v) D^2) + k.
/// Inputs in SI: T in N, p_0 and p_v in Pa, D in m. Returns
/// dimensionless minimum A_E / A_0.
pub fn minimumBladeAreaRatio(
    Z_blades: u32,
    T_n: f64,
    p0_pa: f64,
    pv_pa: f64,
    D_m: f64,
    K: f64,
) Error!f64 {
    if (Z_blades < 2 or Z_blades > 7) return Error.InvalidBladeCount;
    if (!(T_n > 0)) return Error.NonPositiveThrust;
    if (!(D_m > 0)) return Error.NonPositiveDiameter;
    if (!(p0_pa > pv_pa)) return Error.NonPositivePressure;
    const Z_f: f64 = @floatFromInt(Z_blades);
    const denom = (p0_pa - pv_pa) * D_m * D_m;
    return (1.3 + 0.3 * Z_f) * T_n / denom + K;
}

test "Keller minimum BAR: 4-blade single-screw merchant example" {
    // Typical 4-blade single-screw merchant: T = 1.2 MN, D = 6 m,
    // p_0 - p_v = 1.5e5 Pa, K = 0.20.
    // (1.3 + 0.3 * 4) * 1.2e6 / (1.5e5 * 36) + 0.20
    //   = 2.5 * 1.2e6 / 5.4e6 + 0.20
    //   = 3.0e6 / 5.4e6 + 0.20
    //   = 0.5556 + 0.20 = 0.7556.
    const ae_a0 = try minimumBladeAreaRatio(4, 1.2e6, 1.5e5 + 2300.0, 2300.0, 6.0, k_single_screw);
    try std.testing.expectApproxEqAbs(@as(f64, 0.7556), ae_a0, 1e-3);
}

test "Keller minimum BAR scales linearly in thrust" {
    const ae1 = try minimumBladeAreaRatio(4, 1.0e6, 1.5e5 + 2300.0, 2300.0, 6.0, 0.0);
    const ae2 = try minimumBladeAreaRatio(4, 2.0e6, 1.5e5 + 2300.0, 2300.0, 6.0, 0.0);
    try std.testing.expectApproxEqAbs(2.0 * ae1, ae2, 1e-9);
}

test "Keller minimum BAR scales inversely with D^2" {
    const ae_small = try minimumBladeAreaRatio(4, 1.0e6, 1.5e5 + 2300.0, 2300.0, 4.0, 0.0);
    const ae_large = try minimumBladeAreaRatio(4, 1.0e6, 1.5e5 + 2300.0, 2300.0, 8.0, 0.0);
    // D ratio 2 -> D^2 ratio 4 -> ae ratio 1/4.
    try std.testing.expectApproxEqAbs(ae_small / 4.0, ae_large, 1e-9);
}

test "Keller minimum BAR is monotone increasing in Z" {
    const ae3 = try minimumBladeAreaRatio(3, 1.0e6, 1.5e5 + 2300.0, 2300.0, 6.0, 0.0);
    const ae5 = try minimumBladeAreaRatio(5, 1.0e6, 1.5e5 + 2300.0, 2300.0, 6.0, 0.0);
    try std.testing.expect(ae5 > ae3);
}

test "Keller K offset distinguishes single vs twin screw" {
    const ae_single = try minimumBladeAreaRatio(4, 1.0e6, 1.5e5 + 2300.0, 2300.0, 6.0, k_single_screw);
    const ae_twin = try minimumBladeAreaRatio(4, 1.0e6, 1.5e5 + 2300.0, 2300.0, 6.0, k_twin_screw);
    try std.testing.expectApproxEqAbs(ae_single - ae_twin, k_single_screw, 1e-12);
}

test "Keller: invalid blade count rejected" {
    try std.testing.expectError(Error.InvalidBladeCount, minimumBladeAreaRatio(1, 1.0e6, 1.5e5 + 2300.0, 2300.0, 6.0, 0.0));
    try std.testing.expectError(Error.InvalidBladeCount, minimumBladeAreaRatio(8, 1.0e6, 1.5e5 + 2300.0, 2300.0, 6.0, 0.0));
}

test "Keller: non-positive thrust rejected" {
    try std.testing.expectError(Error.NonPositiveThrust, minimumBladeAreaRatio(4, 0.0, 1.5e5 + 2300.0, 2300.0, 6.0, 0.0));
}

test "Keller: p_v >= p_0 rejected" {
    try std.testing.expectError(Error.NonPositivePressure, minimumBladeAreaRatio(4, 1.0e6, 2300.0, 2300.0, 6.0, 0.0));
}
