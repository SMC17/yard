const std = @import("std");

pub const Error = error{
    NonPositiveSpinRatio,
    NonPositiveRadius,
    NonPositiveSpeed,
    NonPositiveRpm,
};

/// Spin ratio SR = omega R / V where omega is the rotor angular
/// velocity in rad/s, R the radius, V the apparent wind speed.
pub fn spinRatio(omega_rps: f64, R_m: f64, V_mps: f64) Error!f64 {
    if (!(omega_rps > 0)) return Error.NonPositiveRpm;
    if (!(R_m > 0)) return Error.NonPositiveRadius;
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    return omega_rps * R_m / V_mps;
}

/// Convert RPM to angular velocity:
///   omega = 2 pi rpm / 60.
pub fn rpmToRps(rpm: f64) Error!f64 {
    if (!(rpm > 0)) return Error.NonPositiveRpm;
    return 2.0 * std.math.pi * rpm / 60.0;
}

/// Maximum practical lift coefficient achieved by a Flettner rotor
/// (Thom 1934 wind-tunnel data). Operational rotors are typically
/// designed for C_L between 4 and 10.
pub const C_L_max: f64 = 12.0;

/// Saturated lift coefficient: linear in SR up to the saturation
/// point, then clipped to `C_L_max`.
pub fn liftCoefficientFromSpinRatio(SR: f64) Error!f64 {
    if (!(SR >= 0)) return Error.NonPositiveSpinRatio;
    const C_L = 0.7 * SR;
    if (C_L > C_L_max) return C_L_max;
    return C_L;
}

/// Drag coefficient envelope:
///   C_D = 0.5 + 0.2 SR^2 / (1 + 0.2 SR^2)
/// The stationary-cylinder drag is ~0.5 (smooth subcritical),
/// rising asymptotically to ~ 1.5 at large SR.
pub fn dragCoefficientFromSpinRatio(SR: f64) Error!f64 {
    if (!(SR >= 0)) return Error.NonPositiveSpinRatio;
    const sr2 = SR * SR;
    return 0.5 + 0.2 * sr2 / (1.0 + 0.2 * sr2);
}

/// Lift-to-drag ratio at the given spin ratio.
pub fn liftToDragRatio(SR: f64) Error!f64 {
    const C_L = try liftCoefficientFromSpinRatio(SR);
    const C_D = try dragCoefficientFromSpinRatio(SR);
    return C_L / C_D;
}

test "spin ratio: 100 RPM, R = 2 m, V = 10 m/s" {
    const omega = try rpmToRps(100.0);
    const SR = try spinRatio(omega, 2.0, 10.0);
    const expected = omega * 2.0 / 10.0;
    try std.testing.expectApproxEqAbs(expected, SR, 1e-9);
}

test "RPM-to-RPS conversion: 60 rpm = 2 pi rad/s" {
    const omega = try rpmToRps(60.0);
    try std.testing.expectApproxEqAbs(2.0 * std.math.pi, omega, 1e-12);
}

test "C_L = 0.7 SR below saturation" {
    const C_L = try liftCoefficientFromSpinRatio(5.0);
    try std.testing.expectApproxEqAbs(@as(f64, 3.5), C_L, 1e-12);
}

test "C_L saturates at C_L_max above the cap" {
    const C_L = try liftCoefficientFromSpinRatio(20.0);
    try std.testing.expectApproxEqAbs(C_L_max, C_L, 1e-12);
}

test "C_L at SR = 0 is zero" {
    const C_L = try liftCoefficientFromSpinRatio(0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), C_L, 1e-12);
}

test "C_D at SR = 0 equals 0.5 (stationary cylinder)" {
    const C_D = try dragCoefficientFromSpinRatio(0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), C_D, 1e-12);
}

test "C_D asymptotes toward 1.5 at large SR" {
    const C_D_huge = try dragCoefficientFromSpinRatio(1000.0);
    try std.testing.expect(C_D_huge > 1.49 and C_D_huge < 1.5);
}

test "C_D monotone increasing in SR" {
    const C_D_1 = try dragCoefficientFromSpinRatio(1.0);
    const C_D_5 = try dragCoefficientFromSpinRatio(5.0);
    const C_D_10 = try dragCoefficientFromSpinRatio(10.0);
    try std.testing.expect(C_D_1 < C_D_5);
    try std.testing.expect(C_D_5 < C_D_10);
}

test "L/D grows monotonically across the operational SR range" {
    const ld_2 = try liftToDragRatio(2.0);
    const ld_5 = try liftToDragRatio(5.0);
    const ld_15 = try liftToDragRatio(15.0);
    // Below saturation, C_L grows linearly while C_D saturates around
    // 1.5, so L/D keeps increasing with SR. After C_L saturation
    // (SR > C_L_max / 0.7 ~ 17.14) the ratio plateaus.
    try std.testing.expect(ld_5 > ld_2);
    try std.testing.expect(ld_15 > ld_5);
}

test "L/D at SR = 0 is zero" {
    const ld = try liftToDragRatio(0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), ld, 1e-12);
}

test "input rejection: negative SR" {
    try std.testing.expectError(Error.NonPositiveSpinRatio, liftCoefficientFromSpinRatio(-0.5));
}

test "input rejection: zero V in spin ratio" {
    try std.testing.expectError(Error.NonPositiveSpeed, spinRatio(10.0, 2.0, 0.0));
}

test "input rejection: zero RPM" {
    try std.testing.expectError(Error.NonPositiveRpm, rpmToRps(0.0));
}
