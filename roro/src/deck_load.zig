const std = @import("std");

pub const Error = error{
    NonPositiveMass,
    NonPositiveGravity,
    InvalidRollAngle,
    NegativeAcceleration,
};

/// Apparent weight on a moving deck:
///   W_apparent = m (g + a_v)
/// `a_v` is positive upward (i.e. a_v > 0 in the upward heave-phase
/// of the ship motion increases the apparent weight).
pub fn apparentWeightN(m_kg: f64, g_mps2: f64, a_v_mps2: f64) Error!f64 {
    if (!(m_kg > 0)) return Error.NonPositiveMass;
    if (!(g_mps2 > 0)) return Error.NonPositiveGravity;
    return m_kg * (g_mps2 + a_v_mps2);
}

/// Lateral lashing load on a vehicle:
///   F_h = m (a_h + g sin(phi))
/// `phi` is the roll angle [rad], range [-pi/2, pi/2]. `a_h` is the
/// lateral acceleration at the deck level [m/s^2].
pub fn lateralLashingForceN(
    m_kg: f64,
    g_mps2: f64,
    a_h_mps2: f64,
    phi_rad: f64,
) Error!f64 {
    if (!(m_kg > 0)) return Error.NonPositiveMass;
    if (!(g_mps2 > 0)) return Error.NonPositiveGravity;
    if (!(phi_rad >= -std.math.pi / 2.0 and phi_rad <= std.math.pi / 2.0)) {
        return Error.InvalidRollAngle;
    }
    return m_kg * (a_h_mps2 + g_mps2 * @sin(phi_rad));
}

/// Tilt of the apparent gravity vector when a vehicle is on a heeled
/// deck under combined a_v + a_h + g:
///   alpha_g = atan2(a_h + g sin phi, g + a_v - g (1 - cos phi)).
/// Useful for verifying tipping stability against the wheel base.
pub fn apparentGravityTiltRad(
    g_mps2: f64,
    a_v_mps2: f64,
    a_h_mps2: f64,
    phi_rad: f64,
) Error!f64 {
    if (!(g_mps2 > 0)) return Error.NonPositiveGravity;
    if (!(phi_rad >= -std.math.pi / 2.0 and phi_rad <= std.math.pi / 2.0)) {
        return Error.InvalidRollAngle;
    }
    const num = a_h_mps2 + g_mps2 * @sin(phi_rad);
    const den = g_mps2 + a_v_mps2 - g_mps2 * (1.0 - @cos(phi_rad));
    return std.math.atan2(num, den);
}

pub const Verdict = enum {
    /// Apparent-gravity tilt < tipping angle: vehicle stays planted.
    pass,
    /// Tilt >= tipping angle: vehicle tips (lashing must restrain).
    fail,
};

/// Vehicle tipping angle from wheel-base half-width `b/2` and centre-
/// of-gravity height `h`:
///   tipping_angle = atan(b / (2 h)).
pub fn tippingAngleRad(b_m: f64, h_cg_m: f64) Error!f64 {
    if (!(b_m > 0)) return Error.NonPositiveMass;
    if (!(h_cg_m > 0)) return Error.NonPositiveMass;
    return std.math.atan(b_m / (2.0 * h_cg_m));
}

pub fn tippingVerdict(alpha_g_rad: f64, alpha_tipping_rad: f64) Verdict {
    if (@abs(alpha_g_rad) < alpha_tipping_rad) return .pass;
    return .fail;
}

test "apparent weight at rest equals m g" {
    const W = try apparentWeightN(1000.0, 9.81, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 9810.0), W, 1e-9);
}

test "apparent weight under positive vertical acceleration increases" {
    const W = try apparentWeightN(1000.0, 9.81, 5.0);
    try std.testing.expectApproxEqAbs(@as(f64, 14_810.0), W, 1e-9);
}

test "apparent weight under negative vertical acceleration decreases" {
    const W = try apparentWeightN(1000.0, 9.81, -3.0);
    try std.testing.expectApproxEqAbs(@as(f64, 6810.0), W, 1e-9);
}

test "apparent weight at free-fall is zero" {
    const W = try apparentWeightN(1000.0, 9.81, -9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), W, 1e-9);
}

test "lateral lashing force at phi = 0, a_h = 0 is zero" {
    const F = try lateralLashingForceN(1000.0, 9.81, 0.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), F, 1e-9);
}

test "lateral lashing force at phi = 30 deg, a_h = 0 is m g sin 30" {
    const F = try lateralLashingForceN(1000.0, 9.81, 0.0, std.math.pi / 6.0);
    const expected = 1000.0 * 9.81 * 0.5;
    try std.testing.expectApproxEqAbs(expected, F, 1e-9);
}

test "lateral lashing force scales linearly with mass" {
    const F1 = try lateralLashingForceN(1000.0, 9.81, 2.0, 0.1);
    const F2 = try lateralLashingForceN(2000.0, 9.81, 2.0, 0.1);
    try std.testing.expectApproxEqAbs(2.0 * F1, F2, 1e-9);
}

test "tipping angle for b/h = 2 yields atan(1) = pi/4" {
    const t = try tippingAngleRad(2.0, 1.0);
    try std.testing.expectApproxEqAbs(std.math.pi / 4.0, t, 1e-12);
}

test "tipping angle for narrow tall vehicle is small" {
    const t = try tippingAngleRad(1.0, 5.0);
    // atan(1 / 10) = 0.0997 rad ~ 5.7 deg.
    try std.testing.expectApproxEqAbs(std.math.atan(@as(f64, 0.1)), t, 1e-12);
}

test "tipping verdict pass when alpha_g < tipping" {
    const at = try tippingAngleRad(2.0, 1.0);
    try std.testing.expectEqual(Verdict.pass, tippingVerdict(std.math.pi / 6.0, at));
}

test "tipping verdict fail when alpha_g >= tipping" {
    const at = try tippingAngleRad(2.0, 1.0);
    try std.testing.expectEqual(Verdict.fail, tippingVerdict(std.math.pi / 3.0, at));
}

test "apparent gravity tilt at phi=0, a_h=0 is zero" {
    const a = try apparentGravityTiltRad(9.81, 0.0, 0.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), a, 1e-12);
}

test "apparent gravity tilt at zero accel, phi = 30 deg is 30 deg" {
    const a = try apparentGravityTiltRad(9.81, 0.0, 0.0, std.math.pi / 6.0);
    // num = g sin(30) = g/2, den = g + 0 - g(1 - cos(30)) = g cos(30)
    // alpha = atan(sin/cos) = 30 deg.
    try std.testing.expectApproxEqAbs(std.math.pi / 6.0, a, 1e-9);
}

test "input rejection: zero mass" {
    try std.testing.expectError(Error.NonPositiveMass, apparentWeightN(0.0, 9.81, 0.0));
}

test "input rejection: roll angle > pi/2" {
    try std.testing.expectError(Error.InvalidRollAngle, lateralLashingForceN(1000.0, 9.81, 0.0, 2.0));
}
