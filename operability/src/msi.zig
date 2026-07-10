//! Motion Sickness Incidence — O'Hanlon & McCauley (1974), the model
//! behind ISO 2631-1's motion-sickness dose and every seakeeping
//! habitability assessment (form as given in Lloyd, "Seakeeping"):
//!
//!   MSI% = 100 * Phi( (log10(a_v / g) - mu) / 0.4 )
//!   mu   = 0.654 + 3.697 log10(f_e) + 2.320 (log10 f_e)^2
//!
//! a_v: vertical acceleration magnitude [m/s^2], f_e: encounter frequency
//! [Hz], 2-hour exposure of unadapted subjects. Peak human sensitivity sits
//! near 0.17 Hz — exactly the heave band of a ship in a seaway, which is
//! why ships make people sick and cars do not.

const std = @import("std");

pub const g: f64 = 9.80665;

/// Abramowitz & Stegun 7.1.26 rational approximation (|err| < 1.5e-7).
pub fn erf(x: f64) f64 {
    const sign: f64 = if (x < 0) -1.0 else 1.0;
    const ax = @abs(x);
    const t = 1.0 / (1.0 + 0.3275911 * ax);
    const y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * @exp(-ax * ax);
    return sign * y;
}

fn phi(z: f64) f64 {
    return 0.5 * (1.0 + erf(z / std.math.sqrt2));
}

/// Percentage of unadapted subjects sick within 2 hours.
pub fn msiPercent(vert_accel_ms2: f64, encounter_freq_hz: f64) f64 {
    if (vert_accel_ms2 <= 0 or encounter_freq_hz <= 0) return 0;
    const lf = std.math.log10(encounter_freq_hz);
    const mu = 0.654 + 3.697 * lf + 2.320 * lf * lf;
    const z = (std.math.log10(vert_accel_ms2 / g) - mu) / 0.4;
    return 100.0 * phi(z);
}

test "erf hand checks (within the approximation's 1.5e-7 bound)" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), erf(0.0), 1.5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8427007929), erf(1.0), 1.5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, -0.8427007929), erf(-1.0), 1.5e-7);
}

test "50% MSI near 0.15 g at the most provocative frequency" {
    // At f = 0.167 Hz, mu = -0.818, so a = 0.152 g gives z ~ 0 -> ~50%.
    const msi = msiPercent(0.152 * g, 0.167);
    try std.testing.expect(msi > 45.0 and msi < 55.0);
}

test "peak sensitivity sits near 0.17 Hz" {
    const a = 1.0; // m/s^2
    const at_peak = msiPercent(a, 0.167);
    try std.testing.expect(at_peak > msiPercent(a, 0.05));
    try std.testing.expect(at_peak > msiPercent(a, 0.5));
    try std.testing.expect(at_peak > msiPercent(a, 1.0));
}

test "MSI increases monotonically with acceleration" {
    const f = 0.167;
    try std.testing.expect(msiPercent(0.5, f) < msiPercent(1.0, f));
    try std.testing.expect(msiPercent(1.0, f) < msiPercent(2.0, f));
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), msiPercent(0.0, f), 1e-12);
}
