// Spectral moments and derived wave-height / period statistics.
//
//   m_n = integral_0^infinity omega^n S(omega) domega
//
// Numerical integration uses composite Simpson 1/3 over a caller-
// supplied truncation [omega_lo, omega_hi] and an odd ordinate count.
// For ITTC modified PM with H_s = 4 m and T_z = 8 s the integral
// recovers H_s = 4 * sqrt(m_0) and T_z = 2 pi sqrt(m_0 / m_2) when
// the truncation is sufficiently wide and the sample count is
// sufficiently dense.
//
// Derived statistics:
//   H_s = 4 sqrt(m_0)                    significant wave height
//   T_z = 2 pi sqrt(m_0 / m_2)           zero-up-crossing period

const std = @import("std");
const spectra = @import("spectra.zig");

pub const Error = error{
    InvalidOrdinateCount,
    NonPositiveSpacing,
    NonPositiveMoment,
};

/// Spectral moment m_n of the ITTC modified PM spectrum over [omega_lo,
/// omega_hi] sampled at `samples` evenly-spaced angular frequencies.
///
/// samples must be odd (>= 3) for Simpson 1/3.
/// Streaming Simpson 1/3 (no allocation; integrand computed inline).
pub fn momentITTC(
    n: u8,
    H_s: f64,
    T_z: f64,
    omega_lo: f64,
    omega_hi: f64,
    samples: usize,
) Error!f64 {
    if (samples < 3 or samples % 2 == 0) return Error.InvalidOrdinateCount;
    if (!(omega_hi > omega_lo)) return Error.NonPositiveSpacing;

    const dx = (omega_hi - omega_lo) / @as(f64, @floatFromInt(samples - 1));
    const power = @as(f64, @floatFromInt(n));

    const f_lo = std.math.pow(f64, omega_lo, power) * spectra.ittcModifiedPM(omega_lo, H_s, T_z);
    const f_hi = std.math.pow(f64, omega_hi, power) * spectra.ittcModifiedPM(omega_hi, H_s, T_z);
    var sum: f64 = f_lo + f_hi;

    var i: usize = 1;
    while (i < samples - 1) : (i += 1) {
        const omega = omega_lo + @as(f64, @floatFromInt(i)) * dx;
        const integrand = std.math.pow(f64, omega, power) * spectra.ittcModifiedPM(omega, H_s, T_z);
        const coeff: f64 = if (i % 2 == 1) 4.0 else 2.0;
        sum += coeff * integrand;
    }
    return sum * dx / 3.0;
}

/// Significant wave height H_s = 4 sqrt(m_0).
pub fn hsFromM0(m_0: f64) Error!f64 {
    if (m_0 <= 0.0) return Error.NonPositiveMoment;
    return 4.0 * @sqrt(m_0);
}

/// Zero-up-crossing period T_z = 2 pi sqrt(m_0 / m_2).
pub fn tzFromMoments(m_0: f64, m_2: f64) Error!f64 {
    if (m_0 <= 0.0 or m_2 <= 0.0) return Error.NonPositiveMoment;
    return 2.0 * std.math.pi * @sqrt(m_0 / m_2);
}

const expectApproxEqRel = std.testing.expectApproxEqRel;

test "ITTC m_0 recovers (H_s / 4)^2 within Simpson tolerance" {
    // H_s = 4 -> m_0 should be (4/4)^2 = 1.0 m^2 (exact for the
    // analytical infinite integral).
    const H_s: f64 = 4.0;
    const T_z: f64 = 8.0;
    const m0 = try momentITTC(0, H_s, T_z, 0.001, 4.0, 8001);
    std.debug.print("\n[VERIFICATION] Calculated ITTC m_0: {d}\n", .{m0});
    try expectApproxEqRel(@as(f64, 1.0), m0, 1e-3);
}

test "ITTC roundtrip recovers H_s within 1 percent" {
    const H_s_input: f64 = 4.0;
    const T_z: f64 = 8.0;
    const m0 = try momentITTC(0, H_s_input, T_z, 0.001, 4.0, 8001);
    const H_s_out = try hsFromM0(m0);
    try expectApproxEqRel(H_s_input, H_s_out, 0.01);
}

test "ITTC roundtrip recovers T_z within 5 percent" {
    const H_s: f64 = 4.0;
    const T_z_input: f64 = 8.0;
    const m0 = try momentITTC(0, H_s, T_z_input, 0.001, 4.0, 8001);
    const m2 = try momentITTC(2, H_s, T_z_input, 0.001, 4.0, 8001);
    const T_z_out = try tzFromMoments(m0, m2);
    try expectApproxEqRel(T_z_input, T_z_out, 0.05);
}

test "hsFromM0 rejects non-positive m_0" {
    try std.testing.expectError(Error.NonPositiveMoment, hsFromM0(0.0));
    try std.testing.expectError(Error.NonPositiveMoment, hsFromM0(-1.0));
}

test "tzFromMoments rejects non-positive moments" {
    try std.testing.expectError(Error.NonPositiveMoment, tzFromMoments(0.0, 1.0));
    try std.testing.expectError(Error.NonPositiveMoment, tzFromMoments(1.0, 0.0));
}

test "momentITTC rejects even sample count" {
    try std.testing.expectError(Error.InvalidOrdinateCount, momentITTC(0, 4.0, 8.0, 0.01, 4.0, 100));
}

test "momentITTC rejects inverted range" {
    try std.testing.expectError(Error.NonPositiveSpacing, momentITTC(0, 4.0, 8.0, 4.0, 0.01, 1001));
}
