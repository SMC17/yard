const std = @import("std");

pub const Error = error{
    NonPositiveInertia,
    NonPositiveDisplacement,
    NonPositiveLength,
    InvalidCalibrationCoefficient,
};

/// Schlick coefficient for typical merchant ships in SI units when
/// I is in m^4, Delta in tonnes, L in metres, returning f_2 in Hz.
pub const phi_schlick_merchant_si: f64 = 32_000.0;

/// Two-node vertical hull-girder bending natural frequency per
/// Schlick's empirical formula:
///   f_2 = phi sqrt(I_v / (Delta L^3))
/// Returns Hz.
pub fn twoNodeBendingHz(
    I_v_m4: f64,
    Delta_t: f64,
    L_m: f64,
    phi: f64,
) Error!f64 {
    if (!(I_v_m4 > 0)) return Error.NonPositiveInertia;
    if (!(Delta_t > 0)) return Error.NonPositiveDisplacement;
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (!(phi > 0)) return Error.InvalidCalibrationCoefficient;
    return phi * @sqrt(I_v_m4 / (Delta_t * L_m * L_m * L_m));
}

/// Convert two-node frequency to angular frequency omega = 2 pi f.
pub fn twoNodeBendingRps(f_hz: f64) f64 {
    return 2.0 * std.math.pi * f_hz;
}

/// Mode-1 free-decay (springing) period: T = 1 / f_2.
pub fn twoNodePeriodSec(f_hz: f64) f64 {
    return 1.0 / f_hz;
}

test "Schlick formula for a 200 m, 50000 t bulk carrier I = 200 m^4" {
    // f_2 = 32000 * sqrt(200 / (50000 * 8e6))
    //     = 32000 * sqrt(5e-7)
    //     = 32000 * 7.07e-4
    //     = 22.6 Hz (this is a high frequency for a real ship; the
    //     formula calibration depends on phi; here we just exercise
    //     the closed form).
    const f = try twoNodeBendingHz(200.0, 50_000.0, 200.0, phi_schlick_merchant_si);
    const expected = 32_000.0 * @sqrt(200.0 / (50_000.0 * 8.0e6));
    try std.testing.expectApproxEqAbs(expected, f, 1e-9);
}

test "frequency scales with sqrt(I)" {
    const f1 = try twoNodeBendingHz(100.0, 10_000.0, 100.0, 1.0);
    const f2 = try twoNodeBendingHz(400.0, 10_000.0, 100.0, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), f2 / f1, 1e-12);
}

test "frequency scales with 1 / L^(3/2)" {
    const f1 = try twoNodeBendingHz(100.0, 10_000.0, 100.0, 1.0);
    const f2 = try twoNodeBendingHz(100.0, 10_000.0, 200.0, 1.0);
    // L^3 ratio is 8; sqrt(1/8) = 0.3536. f2 / f1 = 0.3536.
    const expected = @sqrt(1.0 / 8.0);
    try std.testing.expectApproxEqAbs(expected, f2 / f1, 1e-9);
}

test "frequency scales with 1 / sqrt(Delta)" {
    const f1 = try twoNodeBendingHz(100.0, 10_000.0, 100.0, 1.0);
    const f2 = try twoNodeBendingHz(100.0, 40_000.0, 100.0, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), f2 / f1, 1e-12);
}

test "angular frequency 2 pi conversion" {
    try std.testing.expectApproxEqAbs(2.0 * std.math.pi, twoNodeBendingRps(1.0), 1e-12);
}

test "period 1 / f closed form" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), twoNodePeriodSec(2.0), 1e-12);
}

test "input rejection: zero displacement" {
    try std.testing.expectError(Error.NonPositiveDisplacement, twoNodeBendingHz(100.0, 0.0, 100.0, 1.0));
}

test "input rejection: zero phi" {
    try std.testing.expectError(Error.InvalidCalibrationCoefficient, twoNodeBendingHz(100.0, 10_000.0, 100.0, 0.0));
}
