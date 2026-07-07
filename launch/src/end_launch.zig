const std = @import("std");

pub const Error = error{
    NonPositiveMass,
    NonPositiveDistance,
    InvalidDeclivity,
    InvalidFrictionCoefficient,
};

/// Net acceleration of the ship sliding down the ways:
///   a = g (sin(alpha) - mu cos(alpha))
/// alpha is the slipway declivity in radians (typ. 1:18 = 0.0555
/// rad), mu is the kinetic friction coefficient between the ship's
/// cradle / grease and the timber way (typ. 0.02-0.05).
pub fn slidingAccelerationMPS2(
    alpha_rad: f64,
    mu: f64,
    g_mps2: f64,
) Error!f64 {
    if (!(alpha_rad >= 0 and alpha_rad <= std.math.pi / 4.0)) return Error.InvalidDeclivity;
    if (!(mu >= 0 and mu <= 1.0)) return Error.InvalidFrictionCoefficient;
    return g_mps2 * (@sin(alpha_rad) - mu * @cos(alpha_rad));
}

/// Way-end velocity from energy balance (starting from rest):
///   v = sqrt(2 a L)
/// where L is the distance the ship slides from rest to the way-end
/// and a is the net sliding acceleration.
pub fn wayEndVelocityMPerS(
    a_mps2: f64,
    L_m: f64,
) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveDistance;
    if (a_mps2 <= 0) return 0.0;
    return @sqrt(2.0 * a_mps2 * L_m);
}

/// Total kinetic energy at the way-end:
///   E_k = 0.5 m v^2.
pub fn wayEndKineticEnergyJ(m_t: f64, v_mps: f64) Error!f64 {
    if (!(m_t > 0)) return Error.NonPositiveMass;
    return 0.5 * m_t * 1000.0 * v_mps * v_mps;
}

/// Composer: end-launch velocity from declivity / friction / way
/// length.
pub fn velocityFromGeometry(
    alpha_rad: f64,
    mu: f64,
    L_m: f64,
    g_mps2: f64,
) Error!f64 {
    const a = try slidingAccelerationMPS2(alpha_rad, mu, g_mps2);
    return try wayEndVelocityMPerS(a, L_m);
}

test "sliding accel at alpha = 0 and mu = 0 is 0" {
    const a = try slidingAccelerationMPS2(0.0, 0.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), a, 1e-12);
}

test "sliding accel at alpha = 0 and mu > 0 is negative (won't slide)" {
    const a = try slidingAccelerationMPS2(0.0, 0.05, 9.81);
    try std.testing.expect(a < 0);
}

test "sliding accel at typical 1:18 slipway with mu = 0.02" {
    // alpha = arctan(1/18) = 0.0555 rad ~ 3.18 deg.
    // a = 9.81 (sin 0.0555 - 0.02 cos 0.0555) = 9.81 (0.0554 - 0.01998) = 9.81 * 0.0355 = 0.348.
    const alpha = std.math.atan(@as(f64, 1.0 / 18.0));
    const a = try slidingAccelerationMPS2(alpha, 0.02, 9.81);
    const expected = 9.81 * (@sin(alpha) - 0.02 * @cos(alpha));
    try std.testing.expectApproxEqAbs(expected, a, 1e-9);
    try std.testing.expect(a > 0.2 and a < 0.5);
}

test "way-end velocity from 200 m slip at 0.35 m/s^2 acceleration" {
    const v = try wayEndVelocityMPerS(0.35, 200.0);
    try std.testing.expectApproxEqAbs(@sqrt(2.0 * 0.35 * 200.0), v, 1e-9);
    // ~ 11.83 m/s.
    try std.testing.expect(v > 10.0 and v < 13.0);
}

test "way-end velocity zero when acceleration non-positive" {
    const v = try wayEndVelocityMPerS(-0.5, 200.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), v, 1e-12);
}

test "way-end velocity scales with sqrt(L)" {
    const v1 = try wayEndVelocityMPerS(0.5, 100.0);
    const v2 = try wayEndVelocityMPerS(0.5, 400.0);
    try std.testing.expectApproxEqAbs(2.0 * v1, v2, 1e-9);
}

test "kinetic energy at 5000 t and 12 m/s" {
    const E = try wayEndKineticEnergyJ(5000.0, 12.0);
    const expected = 0.5 * 5_000_000.0 * 144.0;
    try std.testing.expectApproxEqAbs(expected, E, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f64, 3.6e8), E, 1e6);
}

test "composer reproduces velocity from geometry" {
    const alpha = std.math.atan(@as(f64, 1.0 / 18.0));
    const v = try velocityFromGeometry(alpha, 0.02, 200.0, 9.81);
    const a = try slidingAccelerationMPS2(alpha, 0.02, 9.81);
    const v_expected = try wayEndVelocityMPerS(a, 200.0);
    try std.testing.expectApproxEqAbs(v_expected, v, 1e-12);
}

test "input rejection: declivity > pi/4" {
    try std.testing.expectError(
        Error.InvalidDeclivity,
        slidingAccelerationMPS2(1.0, 0.02, 9.81),
    );
}

test "input rejection: mu > 1" {
    try std.testing.expectError(
        Error.InvalidFrictionCoefficient,
        slidingAccelerationMPS2(0.05, 1.5, 9.81),
    );
}

test "input rejection: zero L" {
    try std.testing.expectError(Error.NonPositiveDistance, wayEndVelocityMPerS(0.5, 0.0));
}
