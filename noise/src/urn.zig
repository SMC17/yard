const std = @import("std");

pub const Error = error{
    NonPositiveRange,
    NegativeAbsorption,
    NonPositiveFrequency,
};

/// Spherical transmission loss between the source range and the
/// reference range (typically 1 m). `r_m` is the measurement range,
/// `r_ref_m` is the reference range (must be > 0).
pub fn sphericalSpreadingDb(r_m: f64, r_ref_m: f64) Error!f64 {
    if (!(r_m > 0)) return Error.NonPositiveRange;
    if (!(r_ref_m > 0)) return Error.NonPositiveRange;
    return 20.0 * std.math.log10(r_m / r_ref_m);
}

/// Cylindrical transmission loss for waveguide-style propagation
/// at long range:
///   TL = 10 log10(r / r_ref).
pub fn cylindricalSpreadingDb(r_m: f64, r_ref_m: f64) Error!f64 {
    if (!(r_m > 0)) return Error.NonPositiveRange;
    if (!(r_ref_m > 0)) return Error.NonPositiveRange;
    return 10.0 * std.math.log10(r_m / r_ref_m);
}

/// Frequency-dependent absorption coefficient `alpha` in dB/m per a
/// simplified Thorp 1967 fit for sea water at typical conditions.
///   alpha(f) = 1.1e-4 f^2 + 0.011 / (1 + f^2)  (dB/m, f in kHz)
pub fn thorpAbsorptionDbPerM(freq_khz: f64) Error!f64 {
    if (!(freq_khz > 0)) return Error.NonPositiveFrequency;
    const f2 = freq_khz * freq_khz;
    return 1.1e-4 * f2 + 0.011 / (1.0 + f2);
}

/// Total spherical-spreading + absorption transmission loss:
///   TL = 20 log10(r / r_ref) + alpha (r - r_ref).
pub fn transmissionLossDb(r_m: f64, r_ref_m: f64, alpha_db_per_m: f64) Error!f64 {
    if (!(alpha_db_per_m >= 0)) return Error.NegativeAbsorption;
    const TL_spread = try sphericalSpreadingDb(r_m, r_ref_m);
    return TL_spread + alpha_db_per_m * (r_m - r_ref_m);
}

/// Source level SPL_source = SPL_measured + TL [dB re 1 µPa @ 1 m].
pub fn sourceLevelDbReference1m(
    SPL_measured_db: f64,
    r_m: f64,
    alpha_db_per_m: f64,
) Error!f64 {
    const TL = try transmissionLossDb(r_m, 1.0, alpha_db_per_m);
    return SPL_measured_db + TL;
}

test "spherical spreading at r = 1 m equals zero" {
    const TL = try sphericalSpreadingDb(1.0, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), TL, 1e-12);
}

test "spherical spreading 6 dB per doubling of range" {
    const TL_10 = try sphericalSpreadingDb(10.0, 1.0);
    const TL_20 = try sphericalSpreadingDb(20.0, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 6.020599913279624), TL_20 - TL_10, 1e-9);
}

test "spherical spreading 20 dB per decade of range" {
    const TL_10 = try sphericalSpreadingDb(10.0, 1.0);
    const TL_100 = try sphericalSpreadingDb(100.0, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), TL_100 - TL_10, 1e-9);
}

test "cylindrical spreading 3 dB per doubling of range" {
    const TL_10 = try cylindricalSpreadingDb(10.0, 1.0);
    const TL_20 = try cylindricalSpreadingDb(20.0, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 3.010299956639812), TL_20 - TL_10, 1e-9);
}

test "Thorp absorption at 10 kHz is on the order of 0.012 dB/m" {
    const alpha = try thorpAbsorptionDbPerM(10.0);
    // 1.1e-4 * 100 + 0.011 / 101 = 0.011 + 0.0001089 = 0.011109.
    const expected = 1.1e-4 * 100.0 + 0.011 / 101.0;
    try std.testing.expectApproxEqAbs(expected, alpha, 1e-12);
}

test "Thorp absorption at 100 kHz higher than at 10 kHz" {
    const a_10 = try thorpAbsorptionDbPerM(10.0);
    const a_100 = try thorpAbsorptionDbPerM(100.0);
    try std.testing.expect(a_100 > a_10);
}

test "total TL at r = 100, alpha = 0.01: 20 log10(100) + 0.01 * 99 = 40.99" {
    const TL = try transmissionLossDb(100.0, 1.0, 0.01);
    const expected = 20.0 * std.math.log10(100.0) + 0.01 * 99.0;
    try std.testing.expectApproxEqAbs(expected, TL, 1e-12);
}

test "source level at SPL_measured = 100 dB at r = 100 m, alpha = 0" {
    const SL = try sourceLevelDbReference1m(100.0, 100.0, 0.0);
    // SL = 100 + 40 = 140 dB re 1 uPa @ 1 m.
    try std.testing.expectApproxEqAbs(@as(f64, 140.0), SL, 1e-12);
}

test "source level with absorption shifts up by alpha (r - 1)" {
    const SL_no_abs = try sourceLevelDbReference1m(100.0, 100.0, 0.0);
    const SL_abs = try sourceLevelDbReference1m(100.0, 100.0, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 0.99), SL_abs - SL_no_abs, 1e-12);
}

test "input rejection: zero range" {
    try std.testing.expectError(Error.NonPositiveRange, sphericalSpreadingDb(0.0, 1.0));
}

test "input rejection: negative absorption" {
    try std.testing.expectError(Error.NegativeAbsorption, transmissionLossDb(100.0, 1.0, -0.001));
}

test "input rejection: zero frequency" {
    try std.testing.expectError(Error.NonPositiveFrequency, thorpAbsorptionDbPerM(0.0));
}
