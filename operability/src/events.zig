//! Rayleigh-exceedance event statistics for narrow-band Gaussian seaway
//! responses — slamming (Ochi 1964), deck wetness, propeller emergence.
//!
//! For a narrow-band Gaussian process with variance m0, amplitude maxima
//! are Rayleigh distributed:  P(amplitude > a) = exp(-a^2 / (2 m0)).
//!
//! Ochi's slamming criterion: a slam requires simultaneous forefoot
//! emergence (relative bow motion exceeding the local draft) AND relative
//! vertical velocity above the threshold at impact; for independent
//! narrow-band amplitude/velocity this gives
//!   P(slam) = exp(-( d^2 / (2 m0_rel) + v_cr^2 / (2 m0_vel) ))
//! with the classic threshold v_cr = 0.093 sqrt(g L) (Ochi, from model
//! tests; see Faltinsen 1990 ch. 3, Lloyd "Seakeeping").
//!
//! Deck wetness: relative bow motion exceeding the bow freeboard,
//!   P(wet) = exp(-f_b^2 / (2 m0_rel)).
//! Propeller emergence: relative stern motion exceeding the propeller
//! submergence.

const std = @import("std");

pub const g: f64 = 9.80665;

/// P(amplitude > threshold) for a narrow-band response with variance m0.
pub fn rayleighExceedance(threshold: f64, m0: f64) f64 {
    if (m0 <= 0) return 0;
    return @exp(-(threshold * threshold) / (2.0 * m0));
}

/// Ochi threshold velocity for slamming [m/s].
pub fn ochiThresholdVelocity(length_m: f64) f64 {
    return 0.093 * @sqrt(g * length_m);
}

/// Ochi slamming probability per relative-motion cycle at the forefoot.
///   draft_fwd_m: local draft at the station considered
///   m0_rel: variance of relative vertical motion [m^2]
///   m0_vel: variance of relative vertical velocity [(m/s)^2]
pub fn slamProbability(draft_fwd_m: f64, m0_rel: f64, m0_vel: f64, length_m: f64) f64 {
    if (m0_rel <= 0 or m0_vel <= 0) return 0;
    const vcr = ochiThresholdVelocity(length_m);
    return @exp(-(draft_fwd_m * draft_fwd_m / (2.0 * m0_rel) +
        vcr * vcr / (2.0 * m0_vel)));
}

/// Deck wetness probability per cycle from bow freeboard exceedance.
pub fn wetnessProbability(freeboard_bow_m: f64, m0_rel: f64) f64 {
    return rayleighExceedance(freeboard_bow_m, m0_rel);
}

/// Propeller emergence probability per cycle.
pub fn propellerEmergenceProbability(submergence_m: f64, m0_rel_stern: f64) f64 {
    return rayleighExceedance(submergence_m, m0_rel_stern);
}

/// Events per hour given the mean zero-upcrossing period T_z [s].
pub fn eventsPerHour(probability_per_cycle: f64, tz_s: f64) f64 {
    if (tz_s <= 0) return 0;
    return probability_per_cycle * 3600.0 / tz_s;
}

test "Rayleigh exceedance matches hand computation" {
    // m0 = 4 m^2 (RMS 2 m), threshold 4 m: exp(-16/8) = exp(-2) = 0.13534.
    try std.testing.expectApproxEqAbs(@as(f64, 0.1353352832366127), rayleighExceedance(4.0, 4.0), 1e-12);
    // Threshold at RMS: exp(-0.5) = 0.60653.
    try std.testing.expectApproxEqAbs(@as(f64, 0.6065306597126334), rayleighExceedance(2.0, 4.0), 1e-12);
}

test "Ochi threshold velocity for a 140 m hull" {
    // 0.093 sqrt(9.80665 * 140) = 0.093 * 37.05 = 3.446 m/s.
    try std.testing.expectApproxEqAbs(@as(f64, 3.4459), ochiThresholdVelocity(140.0), 1e-3);
}

test "slam probability rises with relative-velocity variance, falls with draft" {
    const base = slamProbability(5.0, 4.0, 4.0, 140.0);
    const faster = slamProbability(5.0, 4.0, 9.0, 140.0); // speed raises m0_vel
    const deeper = slamProbability(7.0, 4.0, 4.0, 140.0);
    try std.testing.expect(faster > base);
    try std.testing.expect(deeper < base);
    try std.testing.expect(base > 0 and base < 1);
}

test "wetness falls exponentially with freeboard" {
    const low = wetnessProbability(3.0, 4.0);
    const high = wetnessProbability(6.0, 4.0);
    try std.testing.expect(high < low);
    // Doubling the threshold quarters the exponent's argument scale:
    // ln P scales with -f^2, hand check: exp(-9/8) vs exp(-36/8).
    try std.testing.expectApproxEqAbs(@exp(@as(f64, -9.0 / 8.0)), low, 1e-12);
    try std.testing.expectApproxEqAbs(@exp(@as(f64, -36.0 / 8.0)), high, 1e-12);
}

test "events per hour from Tz" {
    // P = 0.03 per cycle at Tz = 8 s: 0.03 * 450 cycles/h = 13.5 events/h.
    try std.testing.expectApproxEqAbs(@as(f64, 13.5), eventsPerHour(0.03, 8.0), 1e-9);
}
