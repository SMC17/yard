//! STIR Vulnerability Level 2 — simplified probabilistic exceedance kernels.
//! VL2 supplements VL1 screening per MEPC.1/Circ.1627; not a full time-domain sim.

const std = @import("std");
const dead_ship = @import("dead_ship.zig");
const parametric = @import("parametric.zig");

pub const Error = error{
    InvalidInput,
};

/// Standard normal CDF approximation (Abramowitz & Stegun 26.2.17).
fn normalCdf(x: f64) f64 {
    const a1: f64 = 0.254829592;
    const a2: f64 = -0.284496736;
    const a3: f64 = 1.421413741;
    const a4: f64 = -1.453152027;
    const a5: f64 = 1.061405429;
    const p: f64 = 0.3275911;
    const sign: f64 = if (x < 0.0) -1.0 else 1.0;
    const ax = @abs(x) / @sqrt(2.0);
    const t = 1.0 / (1.0 + p * ax);
    const y = 1.0 - (((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t) * @exp(-ax * ax);
    return 0.5 * (1.0 + sign * y);
}

/// Dead-ship VL2: phi_1 = phi_0 + 1.7 phi_m with phi_m ~ N(mu, sigma^2).
/// Returns exceedance probability P(phi_1 >= phi_F).
pub fn deadShipExceedanceProbability(
    phi_0_rad: f64,
    phi_m_mean_rad: f64,
    phi_m_std_rad: f64,
    phi_F_rad: f64,
) Error!f64 {
    if (!(phi_m_std_rad > 0)) return Error.InvalidInput;
    if (!(phi_F_rad > 0)) return Error.InvalidInput;
    const threshold_m = (phi_F_rad - phi_0_rad) / 1.7;
    const z = (threshold_m - phi_m_mean_rad) / phi_m_std_rad;
    return 1.0 - normalCdf(z);
}

pub const VL2Verdict = enum { pass, fail };

/// Fail if exceedance probability exceeds allowable (default 10^-2 per VL2 spirit).
pub fn deadShipVL2Verdict(probability: f64, allowable: f64) VL2Verdict {
    if (probability > allowable) return .fail;
    return .pass;
}

/// Parametric-roll VL2: encounter frequency uncertainty maps R into resonance band.
/// Returns approximate fraction of sea states with R in [0.85, 1.15].
pub fn parametricResonanceOccupancy(
    R_mean: f64,
    R_std: f64,
) Error!f64 {
    if (!(R_std > 0)) return Error.InvalidInput;
    const p_lo = 1.0 - normalCdf((0.85 - R_mean) / R_std);
    const p_hi = 1.0 - normalCdf((1.15 - R_mean) / R_std);
    return @max(0.0, p_lo - p_hi);
}

pub fn parametricVL2Verdict(occupancy: f64, allowable: f64) VL2Verdict {
    if (occupancy > allowable) return .fail;
    return .pass;
}

test "dead-ship VL2: high sigma increases exceedance" {
    const p_low = try deadShipExceedanceProbability(0.1, 0.15, 0.02, 0.5);
    const p_high = try deadShipExceedanceProbability(0.1, 0.15, 0.10, 0.5);
    try std.testing.expect(p_high > p_low);
}

test "parametric VL2: R=1 centered gives high occupancy" {
    const occ = try parametricResonanceOccupancy(1.0, 0.05);
    try std.testing.expect(occ > 0.5);
}

test "VL1 fail + VL2 low probability can still pass VL2" {
    const phi_0 = try dead_ship.staticHeelAngleSmallAngleRad(2.0e5, 10_000_000.0, 1.0, 9.81);
    const phi_1 = try dead_ship.residualRollAngleRad(phi_0, 0.05);
    _ = dead_ship.verdict(phi_1, 0.6);
    const p = try deadShipExceedanceProbability(phi_0, 0.05, 0.01, 0.6);
    try std.testing.expectEqual(VL2Verdict.pass, deadShipVL2Verdict(p, 0.05));
}