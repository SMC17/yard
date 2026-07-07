const std = @import("std");

pub const Error = error{
    NonPositiveWaveLength,
    NonPositiveDepth,
    NegativeZ,
    InvalidPhase,
};

/// Wave number k from angular frequency omega and water depth h via
/// the linear dispersion relation:
///   omega^2 = g k tanh(k h).
/// Solved by Newton iteration starting from the deep-water initial
/// guess k0 = omega^2 / g.
pub fn waveNumberMInv(omega_rps: f64, h_m: f64, g_mps2: f64) Error!f64 {
    if (!(omega_rps > 0)) return Error.NonPositiveWaveLength;
    if (!(h_m > 0)) return Error.NonPositiveDepth;
    var k = omega_rps * omega_rps / g_mps2;
    var iter: usize = 0;
    while (iter < 100) : (iter += 1) {
        const arg = k * h_m;
        const t = std.math.tanh(arg);
        const f = g_mps2 * k * t - omega_rps * omega_rps;
        const sech2 = 1.0 - t * t;
        const df = g_mps2 * (t + k * h_m * sech2);
        if (@abs(df) < 1e-30) break;
        const dk = -f / df;
        k += dk;
        if (k < 1e-12) k = 1e-12;
        if (@abs(dk) < 1e-12 * k) return k;
    }
    return k;
}

/// Horizontal particle velocity at depth z below mean water level
/// (z >= 0, increasing downward) under a linear airy wave at the
/// instant of phase `phi` and crest passage location x = 0:
///   u = H/2 * omega * cosh(k (h - z)) / sinh(k h) * cos(phi)
/// where H is the wave height (crest-to-trough).
pub fn horizontalVelocityMPerS(
    H_m: f64,
    omega_rps: f64,
    k_m_inv: f64,
    h_m: f64,
    z_below_msl_m: f64,
    phi_rad: f64,
) Error!f64 {
    if (!(h_m > 0)) return Error.NonPositiveDepth;
    if (!(z_below_msl_m >= 0)) return Error.NegativeZ;
    if (!(z_below_msl_m <= h_m)) return Error.NegativeZ;
    return 0.5 * H_m * omega_rps * std.math.cosh(k_m_inv * (h_m - z_below_msl_m)) /
        std.math.sinh(k_m_inv * h_m) * @cos(phi_rad);
}

/// Horizontal particle acceleration:
///   du/dt = -H/2 * omega^2 * cosh(...) / sinh(k h) * sin(phi).
pub fn horizontalAccelerationMPerS2(
    H_m: f64,
    omega_rps: f64,
    k_m_inv: f64,
    h_m: f64,
    z_below_msl_m: f64,
    phi_rad: f64,
) Error!f64 {
    if (!(h_m > 0)) return Error.NonPositiveDepth;
    if (!(z_below_msl_m >= 0)) return Error.NegativeZ;
    if (!(z_below_msl_m <= h_m)) return Error.NegativeZ;
    return -0.5 * H_m * omega_rps * omega_rps *
        std.math.cosh(k_m_inv * (h_m - z_below_msl_m)) /
        std.math.sinh(k_m_inv * h_m) * @sin(phi_rad);
}

test "dispersion relation: deep-water k -> omega^2 / g" {
    // omega = 1, h very large -> tanh ~ 1, k ~ omega^2 / g.
    const k = try waveNumberMInv(1.0, 1000.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 9.81), k, 1e-9);
}

test "dispersion relation: shallow-water k -> omega / sqrt(g h)" {
    // omega = 0.1, h = 1 -> k h small. k = omega / sqrt(g h).
    const omega: f64 = 0.1;
    const h: f64 = 1.0;
    const k = try waveNumberMInv(omega, h, 9.81);
    const k_shallow = omega / @sqrt(9.81 * h);
    try std.testing.expectApproxEqAbs(k_shallow, k, 0.01);
}

test "particle velocity at MSL with crest above" {
    // At z = 0, phi = 0: u = H/2 omega cosh(k h) / sinh(k h) * 1
    // = H/2 omega coth(k h).
    const k = try waveNumberMInv(1.0, 100.0, 9.81);
    const u = try horizontalVelocityMPerS(1.0, 1.0, k, 100.0, 0.0, 0.0);
    // Deep-water (k h >> 1): coth(k h) -> 1, u -> H omega / 2 = 0.5.
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), u, 1e-3);
}

test "particle velocity at trough (phi = pi) is negative of crest" {
    const k = try waveNumberMInv(1.0, 100.0, 9.81);
    const u_crest = try horizontalVelocityMPerS(1.0, 1.0, k, 100.0, 0.0, 0.0);
    const u_trough = try horizontalVelocityMPerS(1.0, 1.0, k, 100.0, 0.0, std.math.pi);
    try std.testing.expectApproxEqAbs(u_crest, -u_trough, 1e-9);
}

test "particle acceleration leads velocity by pi/2" {
    const k = try waveNumberMInv(1.0, 100.0, 9.81);
    const u = try horizontalVelocityMPerS(1.0, 1.0, k, 100.0, 0.0, 0.0);
    const dudt = try horizontalAccelerationMPerS2(1.0, 1.0, k, 100.0, 0.0, -std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(u, dudt, 1e-9);
}

test "velocity decays with depth in deep water" {
    const k = try waveNumberMInv(1.0, 100.0, 9.81);
    const u_surface = try horizontalVelocityMPerS(1.0, 1.0, k, 100.0, 0.0, 0.0);
    const u_deep = try horizontalVelocityMPerS(1.0, 1.0, k, 100.0, 20.0, 0.0);
    try std.testing.expect(u_deep < u_surface);
}

test "input rejection: z > h" {
    const k = try waveNumberMInv(1.0, 10.0, 9.81);
    try std.testing.expectError(Error.NegativeZ, horizontalVelocityMPerS(1.0, 1.0, k, 10.0, 12.0, 0.0));
}
