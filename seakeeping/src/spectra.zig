// Wave power-spectral-density functions.
//
// Pierson-Moskowitz (1964) fully-developed wind sea:
//   S(omega) = (alpha g^2 / omega^5) exp(-beta (omega_0 / omega)^4)
//
// JONSWAP (Hasselmann et al. 1973) fetch-limited:
//   S(omega) = (alpha g^2 / omega^5) exp(-1.25 (omega_p / omega)^4) gamma^r
//   r = exp(-(omega - omega_p)^2 / (2 sigma^2 omega_p^2))
//   sigma = 0.07 for omega <= omega_p, 0.09 for omega > omega_p
//
// ITTC modified Pierson-Moskowitz parametrized by (H_s, T_z):
//   S(omega) = (A / omega^5) exp(-B / omega^4)
//   A = 4 pi^3 H_s^2 / T_z^4
//   B = 16 pi^3 / T_z^4
//
// All spectra return zero at omega = 0 (handled to avoid division by zero).

const std = @import("std");

pub const g: f64 = 9.81;

/// Pierson-Moskowitz (fully-developed wind sea) parametrized by alpha
/// (Phillips constant, typically 0.0081) and omega_0 = g / U_19.5.
pub fn piersonMoskowitz(omega: f64, alpha: f64, omega_0: f64) f64 {
    if (omega <= 0.0) return 0.0;
    const w5 = std.math.pow(f64, omega, 5.0);
    const ratio = omega_0 / omega;
    const exponent = -1.25 * std.math.pow(f64, ratio, 4.0);
    return (alpha * g * g / w5) * @exp(exponent);
}

/// JONSWAP fetch-limited spectrum parametrized by alpha, omega_p (peak
/// angular frequency), and gamma (peak-enhancement factor; gamma = 1
/// reduces to Pierson-Moskowitz).
pub fn jonswap(omega: f64, alpha: f64, omega_p: f64, gamma: f64) f64 {
    if (omega <= 0.0) return 0.0;
    const w5 = std.math.pow(f64, omega, 5.0);
    const ratio = omega_p / omega;
    const base = (alpha * g * g / w5) * @exp(-1.25 * std.math.pow(f64, ratio, 4.0));

    const sigma: f64 = if (omega <= omega_p) 0.07 else 0.09;
    const denom = 2.0 * sigma * sigma * omega_p * omega_p;
    const r = @exp(-(omega - omega_p) * (omega - omega_p) / denom);
    return base * std.math.pow(f64, gamma, r);
}

/// ITTC modified Pierson-Moskowitz spectrum parametrized by significant
/// wave height H_s (m) and zero-up-crossing period T_z (s).
pub fn ittcModifiedPM(omega: f64, H_s: f64, T_z: f64) f64 {
    if (omega <= 0.0) return 0.0;
    const pi3 = std.math.pi * std.math.pi * std.math.pi;
    const Tz4 = T_z * T_z * T_z * T_z;
    const A = 4.0 * pi3 * H_s * H_s / Tz4;
    const B = 16.0 * pi3 / Tz4;
    const w4 = omega * omega * omega * omega;
    const w5 = w4 * omega;
    return (A / w5) * @exp(-B / w4);
}

const expectApproxEqRel = std.testing.expectApproxEqRel;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "piersonMoskowitz returns zero at omega = 0" {
    try expectApproxEqAbs(@as(f64, 0.0), piersonMoskowitz(0.0, 0.0081, 0.5), 1e-15);
}

test "piersonMoskowitz is positive at typical omega" {
    const s = piersonMoskowitz(0.5, 0.0081, 0.5);
    try std.testing.expect(s > 0.0);
}

test "jonswap with gamma=1 equals Pierson-Moskowitz" {
    const omega: f64 = 0.7;
    const alpha: f64 = 0.0081;
    const omega_p: f64 = 0.6;
    const pm = piersonMoskowitz(omega, alpha, omega_p);
    const js = jonswap(omega, alpha, omega_p, 1.0);
    try expectApproxEqRel(pm, js, 1e-12);
}

test "jonswap with gamma > 1 exceeds PM at peak" {
    const omega_p: f64 = 0.6;
    const pm_at_peak = piersonMoskowitz(omega_p, 0.0081, omega_p);
    const js_at_peak = jonswap(omega_p, 0.0081, omega_p, 3.3);
    try std.testing.expect(js_at_peak > pm_at_peak);
}

test "ittcModifiedPM positive at typical omega" {
    const s = ittcModifiedPM(0.5, 4.0, 8.0);
    try std.testing.expect(s > 0.0);
}

test "ittcModifiedPM zero at omega = 0" {
    try expectApproxEqAbs(@as(f64, 0.0), ittcModifiedPM(0.0, 4.0, 8.0), 1e-15);
}

test "ittcModifiedPM scales as H_s squared at fixed T_z" {
    const omega: f64 = 0.7;
    const T_z: f64 = 8.0;
    const s_2 = ittcModifiedPM(omega, 2.0, T_z);
    const s_4 = ittcModifiedPM(omega, 4.0, T_z);
    // S scales as H_s^2; doubling H_s quadruples S.
    try expectApproxEqRel(@as(f64, 4.0), s_4 / s_2, 1e-12);
}

test "ittcModifiedPM peak location and value differ across T_z" {
    // Smaller T_z (shorter period) shifts the spectrum peak to higher omega.
    const tz_short = ittcModifiedPM(1.0, 4.0, 5.0);
    const tz_long = ittcModifiedPM(1.0, 4.0, 10.0);
    try std.testing.expect(tz_short != tz_long);
}
