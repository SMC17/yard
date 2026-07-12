//! Surf-riding / broaching Vulnerability Level 1 screening kernel.
//! Simplified STIR Level 1 criterion: following-sea speed vs wave celerity band.

const std = @import("std");

pub const Error = error{
    NonPositiveSpeed,
    NonPositivePeriod,
    InvalidFroude,
};

/// Deep-water wave celerity from mean zero-crossing period Tz [s].
pub fn waveCelerityMps(Tz_s: f64, g_mps2: f64) Error!f64 {
    if (!(Tz_s > 0)) return Error.NonPositivePeriod;
    return g_mps2 * Tz_s / (2.0 * std.math.pi);
}

/// Surf-riding number: ship speed / wave celerity (following seas proxy).
pub fn surfRidingNumber(V_mps: f64, Tz_s: f64, g_mps2: f64) Error!f64 {
    if (!(V_mps >= 0)) return Error.NonPositiveSpeed;
    const c = try waveCelerityMps(Tz_s, g_mps2);
    return V_mps / c;
}

pub fn froudeNumber(V_mps: f64, L_m: f64, g_mps2: f64) Error!f64 {
    if (!(L_m > 0)) return Error.InvalidFroude;
    if (!(V_mps >= 0)) return Error.NonPositiveSpeed;
    return V_mps / @sqrt(g_mps2 * L_m);
}

pub const Verdict = enum {
    /// Outside surf-riding vulnerability band or low Fn.
    pass,
    /// Speed in surf-riding band with sufficient Fn — VL1 not satisfied.
    fail,
};

/// VL1 broaching screen per STIR following-sea spirit:
/// fail when 0.85 <= surf_riding_number <= 1.15 and Fn >= fn_min.
pub fn verdictVL1(
    surf_riding_number: f64,
    fn_val: f64,
    fn_min: f64,
) Verdict {
    if (surf_riding_number >= 0.85 and surf_riding_number <= 1.15 and fn_val >= fn_min)
        return .fail;
    return .pass;
}

/// Melnikov-style energy threshold proxy: exceedance when kinetic energy ratio
/// (V/c)^2 exceeds threshold in following seas.
pub fn melnikovEnergyRatio(V_mps: f64, Tz_s: f64, g_mps2: f64) Error!f64 {
    const srn = try surfRidingNumber(V_mps, Tz_s, g_mps2);
    return srn * srn;
}

pub fn melnikovVL1Verdict(energy_ratio: f64, threshold: f64) Verdict {
    if (energy_ratio >= threshold) return .fail;
    return .pass;
}

test "wave celerity Tz=8s gives c ≈ 12.5 m/s" {
    const c = try waveCelerityMps(8.0, 9.80665);
    try std.testing.expectApproxEqAbs(12.46, c, 0.1);
}

test "surf-riding number 10 m/s at Tz=8 in vulnerability band" {
    const srn = try surfRidingNumber(10.0, 8.0, 9.80665);
    try std.testing.expect(srn > 0.8 and srn < 1.0);
}

test "VL1 fails for V=12 m/s, L=100, Tz=8" {
    const srn = try surfRidingNumber(12.0, 8.0, 9.80665);
    const fn = try froudeNumber(12.0, 100.0, 9.80665);
    try std.testing.expectEqual(Verdict.fail, verdictVL1(srn, fn, 0.25));
}

test "VL1 passes for slow ship" {
    const srn = try surfRidingNumber(4.0, 8.0, 9.80665);
    const fn = try froudeNumber(4.0, 100.0, 9.80665);
    try std.testing.expectEqual(Verdict.pass, verdictVL1(srn, fn, 0.25));
}