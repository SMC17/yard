const std = @import("std");

pub const Error = error{
    NonPositiveBeam,
    NonPositiveSpeed,
    NonPositiveTrim,
    NonPositiveLambda,
    InvalidDeadrise,
    TrimOutOfSavitskyRange,
    LambdaOutOfSavitskyRange,
};

/// Speed coefficient C_V = V / sqrt(g B). Beam Froude number.
pub fn speedCoefficient(V_mps: f64, B_m: f64, g_mps2: f64) Error!f64 {
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(B_m > 0)) return Error.NonPositiveBeam;
    return V_mps / @sqrt(g_mps2 * B_m);
}

/// Flat-plate lift coefficient per Savitsky 1964:
///   C_L0 = tau^1.1 (0.0120 lambda^0.5 + 0.0055 lambda^2.5 / C_V^2).
/// `tau_deg` is the trim angle in degrees. The original empirical fit
/// is bounded to 2 deg <= tau <= 15 deg, 1 <= lambda <= 4 (the kernel
/// rejects inputs outside that range).
pub fn flatPlateLiftCoefficient(tau_deg: f64, lambda: f64, C_V: f64) Error!f64 {
    if (!(tau_deg > 0)) return Error.NonPositiveTrim;
    if (!(lambda > 0)) return Error.NonPositiveLambda;
    if (!(tau_deg >= 2.0 and tau_deg <= 15.0)) return Error.TrimOutOfSavitskyRange;
    if (!(lambda >= 1.0 and lambda <= 4.0)) return Error.LambdaOutOfSavitskyRange;
    if (!(C_V > 0)) return Error.NonPositiveSpeed;
    const tau_pow = std.math.pow(f64, tau_deg, 1.1);
    const term1 = 0.0120 * std.math.pow(f64, lambda, 0.5);
    const term2 = 0.0055 * std.math.pow(f64, lambda, 2.5) / (C_V * C_V);
    return tau_pow * (term1 + term2);
}

/// Vee-bottom lift coefficient per Savitsky 1964:
///   C_Lbeta = C_L0 - 0.0065 beta C_L0^0.6.
/// `beta_deg` is the deadrise angle [0, 30] degrees. The reduction term
/// can produce a negative lift only for unrealistically low C_L0; if
/// the result is negative, the kernel returns zero.
pub fn veeBottomLiftCoefficient(C_L0: f64, beta_deg: f64) Error!f64 {
    if (!(beta_deg >= 0.0 and beta_deg <= 30.0)) return Error.InvalidDeadrise;
    if (!(C_L0 >= 0)) return Error.NonPositiveTrim;
    const reduced = C_L0 - 0.0065 * beta_deg * std.math.pow(f64, C_L0, 0.6);
    return @max(0.0, reduced);
}

/// Hydrodynamic lift force on the planing surface:
///   L = 0.5 rho V^2 B^2 C_Lbeta.
pub fn hydrodynamicLiftN(
    rho_kg_per_m3: f64,
    V_mps: f64,
    B_m: f64,
    C_Lbeta: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveSpeed;
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(B_m > 0)) return Error.NonPositiveBeam;
    return 0.5 * rho_kg_per_m3 * V_mps * V_mps * B_m * B_m * C_Lbeta;
}

/// Iteratively solve for trim angle tau that produces a lift equal to
/// the displacement weight `W = Delta g`. Inputs: weight `W`, beam
/// `B`, speed `V`, water density `rho`, deadrise `beta_deg`, wetted-
/// length-to-beam ratio `lambda`. Output: trim in degrees in the
/// Savitsky-valid range [2, 15].
pub fn solveTrimDeg(
    W_n: f64,
    B_m: f64,
    V_mps: f64,
    rho_kg_per_m3: f64,
    beta_deg: f64,
    lambda: f64,
    g_mps2: f64,
) Error!f64 {
    if (!(W_n > 0)) return Error.NonPositiveSpeed;
    const C_V = try speedCoefficient(V_mps, B_m, g_mps2);
    // Required C_Lbeta from force balance: 0.5 rho V^2 B^2 C_Lbeta = W
    const cl_required = W_n / (0.5 * rho_kg_per_m3 * V_mps * V_mps * B_m * B_m);
    // Bisection on tau in [2, 15] degrees.
    var lo: f64 = 2.0;
    var hi: f64 = 15.0;
    var iter: usize = 0;
    while (iter < 100) : (iter += 1) {
        const mid = 0.5 * (lo + hi);
        const cl0 = try flatPlateLiftCoefficient(mid, lambda, C_V);
        const clb = try veeBottomLiftCoefficient(cl0, beta_deg);
        if (clb < cl_required) {
            lo = mid;
        } else {
            hi = mid;
        }
        if ((hi - lo) < 1e-9) return 0.5 * (lo + hi);
    }
    return 0.5 * (lo + hi);
}

test "speed coefficient matches V / sqrt(g B)" {
    const C_V = try speedCoefficient(10.0, 4.0, 9.81);
    try std.testing.expectApproxEqAbs(10.0 / @sqrt(39.24), C_V, 1e-12);
}

test "flat-plate lift at tau=4, lambda=2, C_V=4 closed form" {
    // tau^1.1 = 4^1.1 ~ 4.594793, term1 = 0.0120 * sqrt(2) = 0.016971,
    // term2 = 0.0055 * 2^2.5 / 16 = 0.0055 * 5.65685 / 16 = 0.001945.
    // sum ~ 0.018916, * 4.594793 = 0.086911.
    const cl = try flatPlateLiftCoefficient(4.0, 2.0, 4.0);
    const tau_pow = std.math.pow(f64, 4.0, 1.1);
    const term1 = 0.0120 * std.math.pow(f64, 2.0, 0.5);
    const term2 = 0.0055 * std.math.pow(f64, 2.0, 2.5) / 16.0;
    const expected = tau_pow * (term1 + term2);
    try std.testing.expectApproxEqAbs(expected, cl, 1e-12);
}

test "flat-plate lift is monotone increasing in trim" {
    const cl1 = try flatPlateLiftCoefficient(3.0, 2.0, 4.0);
    const cl2 = try flatPlateLiftCoefficient(5.0, 2.0, 4.0);
    try std.testing.expect(cl2 > cl1);
}

test "flat-plate lift is monotone decreasing in C_V (lambda > 0)" {
    const cl1 = try flatPlateLiftCoefficient(4.0, 2.0, 2.0);
    const cl2 = try flatPlateLiftCoefficient(4.0, 2.0, 6.0);
    try std.testing.expect(cl1 > cl2);
}

test "vee-bottom reduces flat-plate at beta > 0" {
    const cl0: f64 = 0.10;
    const clb = try veeBottomLiftCoefficient(cl0, 20.0);
    try std.testing.expect(clb < cl0);
    // Manual: 0.10 - 0.0065 * 20 * 0.10^0.6 = 0.10 - 0.13 * 0.251189 = 0.0673554.
    try std.testing.expectApproxEqAbs(@as(f64, 0.0673554), clb, 1e-5);
}

test "vee-bottom at beta = 0 equals flat plate" {
    const cl0: f64 = 0.08;
    const clb = try veeBottomLiftCoefficient(cl0, 0.0);
    try std.testing.expectApproxEqAbs(cl0, clb, 1e-12);
}

test "vee-bottom clamps to zero on degenerate inputs" {
    const cl0: f64 = 1.0e-6;
    const clb = try veeBottomLiftCoefficient(cl0, 25.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), clb, 1e-12);
}

test "lift force matches force-balance closed form" {
    const L = try hydrodynamicLiftN(1025.0, 15.0, 3.0, 0.1);
    // 0.5 * 1025 * 225 * 9 * 0.1 = 103781.25 N.
    try std.testing.expectApproxEqAbs(@as(f64, 103781.25), L, 1e-6);
}

test "solveTrimDeg converges to a trim that satisfies force balance" {
    // 10-tonne planing hull: W = 10000 * 9.81 = 98100 N.
    // B = 3 m, V = 15 m/s, rho = 1025, beta = 15 deg, lambda = 2.
    const tau = try solveTrimDeg(98_100.0, 3.0, 15.0, 1025.0, 15.0, 2.0, 9.81);
    try std.testing.expect(tau > 2.0 and tau < 15.0);
    // Verify the solved trim reproduces W within 1%.
    const C_V = try speedCoefficient(15.0, 3.0, 9.81);
    const cl0 = try flatPlateLiftCoefficient(tau, 2.0, C_V);
    const clb = try veeBottomLiftCoefficient(cl0, 15.0);
    const L = try hydrodynamicLiftN(1025.0, 15.0, 3.0, clb);
    try std.testing.expectApproxEqAbs(@as(f64, 98_100.0), L, 100.0);
}

test "input rejection: trim out of Savitsky range" {
    try std.testing.expectError(Error.TrimOutOfSavitskyRange, flatPlateLiftCoefficient(1.0, 2.0, 4.0));
    try std.testing.expectError(Error.TrimOutOfSavitskyRange, flatPlateLiftCoefficient(20.0, 2.0, 4.0));
}

test "input rejection: lambda out of Savitsky range" {
    try std.testing.expectError(Error.LambdaOutOfSavitskyRange, flatPlateLiftCoefficient(5.0, 0.5, 4.0));
    try std.testing.expectError(Error.LambdaOutOfSavitskyRange, flatPlateLiftCoefficient(5.0, 5.0, 4.0));
}

test "input rejection: deadrise out of physical range" {
    try std.testing.expectError(Error.InvalidDeadrise, veeBottomLiftCoefficient(0.1, -5.0));
    try std.testing.expectError(Error.InvalidDeadrise, veeBottomLiftCoefficient(0.1, 35.0));
}

test "input rejection: non-positive beam" {
    try std.testing.expectError(Error.NonPositiveBeam, speedCoefficient(10.0, 0.0, 9.81));
    try std.testing.expectError(Error.NonPositiveBeam, hydrodynamicLiftN(1000.0, 10.0, 0.0, 0.1));
}
