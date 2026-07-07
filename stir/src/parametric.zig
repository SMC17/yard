const std = @import("std");

pub const Error = error{
    NonPositiveGM,
    NonPositiveSpeed,
    NonPositiveWaveLength,
    InvalidAngle,
};

/// Wave encounter angular frequency for a ship at heading angle mu
/// (mu = 180 deg means head seas) in regular waves of wave number k
/// and angular frequency omega_w. With deep-water dispersion
/// omega_w = sqrt(g k):
///   omega_e = omega_w - k V cos(mu).
pub fn encounterFrequencyRps(
    omega_w_rps: f64,
    k_m_inv: f64,
    V_mps: f64,
    mu_rad: f64,
) Error!f64 {
    if (!(V_mps >= 0)) return Error.NonPositiveSpeed;
    if (!(omega_w_rps > 0)) return Error.NonPositiveWaveLength;
    if (!(mu_rad >= 0 and mu_rad <= 2.0 * std.math.pi)) return Error.InvalidAngle;
    return omega_w_rps - k_m_inv * V_mps * @cos(mu_rad);
}

/// Natural roll angular frequency from `GM` and roll-radius of
/// gyration k_xx:
///   omega_phi = sqrt(g GM / k_xx^2).
pub fn naturalRollFrequencyRps(GM_m: f64, k_xx_m: f64, g_mps2: f64) Error!f64 {
    if (!(GM_m > 0)) return Error.NonPositiveGM;
    if (!(k_xx_m > 0)) return Error.NonPositiveGM;
    return @sqrt(g_mps2 * GM_m) / k_xx_m;
}

/// Parametric-roll Vulnerability Level 1: dimensionless ratio
///   R = omega_e / (2 omega_phi).
/// Critical band per MEPC.1/Circ.1627 Annex 4: 0.85 <= R <= 1.15
/// (the principal Mathieu instability region around the 2:1 resonance).
pub fn principalMathieuRatio(omega_e: f64, omega_phi: f64) f64 {
    return omega_e / (2.0 * omega_phi);
}

pub const Verdict = enum {
    /// Outside [0.85, 1.15] -- VL1 satisfied for the principal
    /// parametric-roll resonance band.
    pass,
    /// In [0.85, 1.15] -- VL1 not satisfied; second-tier check
    /// (VL2 + direct simulation) required.
    fail,
};

pub fn verdict(R: f64) Verdict {
    if (R >= 0.85 and R <= 1.15) return .fail;
    return .pass;
}

test "encounter frequency: head seas mu = pi yields max omega_e" {
    const V: f64 = 10.0;
    const k: f64 = 0.1;
    const omega_w: f64 = 1.0;
    // Head seas (mu = pi): cos(pi) = -1. omega_e = omega_w - k V * (-1) = 1 + 1 = 2.
    const omega_e = try encounterFrequencyRps(omega_w, k, V, std.math.pi);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), omega_e, 1e-12);
}

test "encounter frequency: following seas mu = 0 yields min omega_e" {
    const V: f64 = 10.0;
    const k: f64 = 0.1;
    const omega_w: f64 = 1.0;
    // mu = 0: omega_e = omega_w - k V = 1 - 1 = 0.
    const omega_e = try encounterFrequencyRps(omega_w, k, V, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), omega_e, 1e-12);
}

test "natural roll frequency: GM = 1, k_xx = 10, g = 9.81" {
    const o = try naturalRollFrequencyRps(1.0, 10.0, 9.81);
    const expected = @sqrt(9.81) / 10.0;
    try std.testing.expectApproxEqAbs(expected, o, 1e-12);
}

test "principal Mathieu ratio: 2:1 resonance gives R = 1.0" {
    // omega_e = 2 omega_phi -> R = 1.
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), principalMathieuRatio(2.0, 1.0), 1e-12);
}

test "verdict: R = 1.0 (2:1 resonance) fails VL1" {
    try std.testing.expectEqual(Verdict.fail, verdict(1.0));
}

test "verdict: R = 0.5 (off-resonance) passes" {
    try std.testing.expectEqual(Verdict.pass, verdict(0.5));
}

test "verdict: R = 1.20 (above band) passes" {
    try std.testing.expectEqual(Verdict.pass, verdict(1.20));
}

test "verdict: R = 0.85 (band edge) fails" {
    try std.testing.expectEqual(Verdict.fail, verdict(0.85));
    try std.testing.expectEqual(Verdict.fail, verdict(1.15));
}

test "input rejection: non-positive GM" {
    try std.testing.expectError(Error.NonPositiveGM, naturalRollFrequencyRps(0.0, 10.0, 9.81));
}

test "input rejection: negative V" {
    try std.testing.expectError(Error.NonPositiveSpeed, encounterFrequencyRps(1.0, 0.1, -5.0, std.math.pi));
}
