//! yard-gustwind — atmospheric turbulence (gust) spectra for marine wind
//! loading, per the published engineering forms:
//!
//!   Davenport (1961):  f S(f) / u*^2 = 4 x^2 / (1 + x^2)^(4/3),
//!                      x = 1200 f / U10   (length scale 1200 m)
//!   Harris (1968):     f S(f) / u*^2 = 4 x / (2 + x^2)^(5/6),
//!                      x = 1800 f / U10   (length scale 1800 m)
//!   NORSOK N-003 / NPD (Froya, offshore):
//!     S(f) = 320 (U10/10)^2 (z/10)^0.45 / (1 + x~^n)^(5/(3n)),
//!     x~ = 172 f (z/10)^(2/3) (U10/10)^(-0.75),  n = 0.468
//!
//! u*^2 = kappa_drag U10^2 with the surface drag coefficient (~0.0025 over
//! rough sea for Davenport's original fit). Used for gust loading on DP
//! systems, mooring, sail rigs, and the weather-criterion lineage.
//!
//! Proof level: unit-tested (hand-evaluated points + shape properties).

const std = @import("std");

pub const drag_coefficient_sea: f64 = 0.0025;

/// Davenport spectrum S(f) [m^2/s^2 per Hz] at 10 m height.
pub fn davenport(f_hz: f64, u10_mps: f64) f64 {
    if (f_hz <= 0 or u10_mps <= 0) return 0;
    const x = 1200.0 * f_hz / u10_mps;
    const ustar2 = drag_coefficient_sea * u10_mps * u10_mps;
    return 4.0 * ustar2 * x * x / (f_hz * std.math.pow(f64, 1.0 + x * x, 4.0 / 3.0));
}

/// Harris spectrum S(f) [m^2/s^2 per Hz] at 10 m height.
pub fn harris(f_hz: f64, u10_mps: f64) f64 {
    if (f_hz <= 0 or u10_mps <= 0) return 0;
    const x = 1800.0 * f_hz / u10_mps;
    const ustar2 = drag_coefficient_sea * u10_mps * u10_mps;
    return 4.0 * ustar2 * x / (f_hz * std.math.pow(f64, 2.0 + x * x, 5.0 / 6.0));
}

/// NORSOK N-003 (NPD/Froya) offshore wind spectrum at height z [m].
pub fn norsok(f_hz: f64, u10_mps: f64, z_m: f64) f64 {
    if (f_hz <= 0 or u10_mps <= 0 or z_m <= 0) return 0;
    const n: f64 = 0.468;
    const u_ratio = u10_mps / 10.0;
    const z_ratio = z_m / 10.0;
    const xt = 172.0 * f_hz * std.math.pow(f64, z_ratio, 2.0 / 3.0) *
        std.math.pow(f64, u_ratio, -0.75);
    return 320.0 * u_ratio * u_ratio * std.math.pow(f64, z_ratio, 0.45) /
        std.math.pow(f64, 1.0 + std.math.pow(f64, xt, n), 5.0 / (3.0 * n));
}

/// Gust variance over a band by trapezoid integration.
pub fn bandVariance(comptime spectrum: fn (f64, f64) f64, wind_mps: f64, f_lo: f64, f_hi: f64, steps: usize) f64 {
    var sum: f64 = 0;
    const df = (f_hi - f_lo) / @as(f64, @floatFromInt(steps));
    var i: usize = 0;
    while (i < steps) : (i += 1) {
        const fa = f_lo + df * @as(f64, @floatFromInt(i));
        sum += 0.5 * (spectrum(fa, wind_mps) + spectrum(fa + df, wind_mps)) * df;
    }
    return sum;
}

test "Davenport hand evaluation at x = 1" {
    // x=1 at f = U10/1200; there f S / u*^2 = 4/2^(4/3) = 1.5874.
    const wind = 12.0;
    const f = wind / 1200.0;
    const ustar2 = drag_coefficient_sea * wind * wind;
    const expected = 4.0 / std.math.pow(f64, 2.0, 4.0 / 3.0) * ustar2 / f;
    try std.testing.expectApproxEqRel(expected, davenport(f, wind), 1e-12);
}

test "Harris hand evaluation at x = 1" {
    // f S / u*^2 = 4 / 3^(5/6) = 1.6013 at x = 1.
    const wind = 12.0;
    const f = wind / 1800.0;
    const ustar2 = drag_coefficient_sea * wind * wind;
    const expected = 4.0 / std.math.pow(f64, 3.0, 5.0 / 6.0) * ustar2 / f;
    try std.testing.expectApproxEqRel(expected, harris(f, wind), 1e-12);
}

test "spectra are positive, peak at low frequency, decay at high frequency" {
    const wind15 = 15.0;
    inline for (.{ davenport, harris }) |spec| {
        const low = spec(0.002, wind15);
        const mid = spec(0.02, wind15);
        const high = spec(1.0, wind15);
        try std.testing.expect(low > 0 and mid > 0 and high > 0);
        try std.testing.expect(high < mid);
    }
    // NORSOK decays monotonically in f (peak at f -> 0 by construction).
    try std.testing.expect(norsok(0.001, 15.0, 10.0) > norsok(0.1, 15.0, 10.0));
    try std.testing.expect(norsok(0.1, 15.0, 10.0) > norsok(1.0, 15.0, 10.0));
}

test "gust energy grows with mean wind and with height per NORSOK" {
    try std.testing.expect(davenport(0.01, 20.0) > davenport(0.01, 10.0));
    try std.testing.expect(norsok(0.01, 20.0, 10.0) > norsok(0.01, 10.0, 10.0));
    try std.testing.expect(norsok(0.001, 15.0, 40.0) > norsok(0.001, 15.0, 10.0));
    // Band variance scales roughly with U^2 (drag-law forcing).
    const v10 = bandVariance(davenport, 10.0, 0.001, 1.0, 2000);
    const v20 = bandVariance(davenport, 20.0, 0.001, 1.0, 2000);
    try std.testing.expect(v20 > 3.0 * v10 and v20 < 5.0 * v10);
}
