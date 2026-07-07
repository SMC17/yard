const std = @import("std");

pub const Error = error{
    NonPositiveDensity,
    NegativeVolumetricFlow,
    NegativeSpeed,
    JetSlowerThanInflow,
};

/// Waterjet net thrust per momentum conservation:
///   T = rho Q (V_j - V_in)
/// All inputs SI; returns N.
pub fn netThrustN(
    rho_kg_per_m3: f64,
    Q_m3_per_s: f64,
    V_j_mps: f64,
    V_in_mps: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(Q_m3_per_s >= 0)) return Error.NegativeVolumetricFlow;
    if (!(V_j_mps >= 0)) return Error.NegativeSpeed;
    if (!(V_in_mps >= 0)) return Error.NegativeSpeed;
    if (!(V_j_mps >= V_in_mps)) return Error.JetSlowerThanInflow;
    return rho_kg_per_m3 * Q_m3_per_s * (V_j_mps - V_in_mps);
}

/// Propulsive efficiency:
///   eta_jet = 2 V_in / (V_j + V_in).
/// Maximum at V_j = V_in (efficiency 1.0 but zero thrust).
pub fn propulsiveEfficiency(V_j_mps: f64, V_in_mps: f64) Error!f64 {
    if (!(V_j_mps > 0)) return Error.NegativeSpeed;
    if (!(V_in_mps > 0)) return Error.NegativeSpeed;
    if (!(V_j_mps >= V_in_mps)) return Error.JetSlowerThanInflow;
    return 2.0 * V_in_mps / (V_j_mps + V_in_mps);
}

/// Jet ideal power = T (V_j + V_in) / 2 [W]. Per the ideal-jet
/// momentum-energy analysis.
pub fn idealJetPowerW(T_n: f64, V_j_mps: f64, V_in_mps: f64) Error!f64 {
    if (!(V_j_mps >= V_in_mps)) return Error.JetSlowerThanInflow;
    if (!(T_n >= 0)) return Error.NegativeSpeed;
    return 0.5 * T_n * (V_j_mps + V_in_mps);
}

test "net thrust at stationary boat: T = rho Q V_j" {
    const T = try netThrustN(1025.0, 5.0, 30.0, 0.0);
    // 1025 * 5 * 30 = 153 750 N.
    try std.testing.expectApproxEqAbs(@as(f64, 153_750.0), T, 1e-9);
}

test "net thrust at V_in = V_j is zero" {
    const T = try netThrustN(1025.0, 5.0, 10.0, 10.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), T, 1e-9);
}

test "net thrust scales linearly with rho" {
    const T1 = try netThrustN(1000.0, 5.0, 30.0, 10.0);
    const T2 = try netThrustN(2000.0, 5.0, 30.0, 10.0);
    try std.testing.expectApproxEqAbs(2.0 * T1, T2, 1e-9);
}

test "propulsive efficiency at V_j = 2 V_in is 2/3" {
    const eta = try propulsiveEfficiency(20.0, 10.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0 / 3.0), eta, 1e-12);
}

test "propulsive efficiency at V_j = V_in is 1.0" {
    const eta = try propulsiveEfficiency(10.0, 10.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), eta, 1e-12);
}

test "propulsive efficiency below 1 for V_j > V_in" {
    const eta = try propulsiveEfficiency(30.0, 5.0);
    try std.testing.expect(eta > 0.0 and eta < 1.0);
}

test "ideal jet power at V_in = 10, V_j = 30, T = 1000 = 20000 W" {
    const P = try idealJetPowerW(1000.0, 30.0, 10.0);
    try std.testing.expectApproxEqAbs(@as(f64, 20_000.0), P, 1e-9);
}

test "input rejection: V_j < V_in" {
    try std.testing.expectError(Error.JetSlowerThanInflow, netThrustN(1025.0, 5.0, 5.0, 10.0));
}

test "input rejection: negative density" {
    try std.testing.expectError(Error.NonPositiveDensity, netThrustN(-1.0, 5.0, 30.0, 10.0));
}
