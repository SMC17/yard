const std = @import("std");

pub const Error = error{
    NonPositiveGain,
    NonPositiveDepth,
    InvalidLimit,
};

/// Proportional-Derivative depth-keeping autopilot. Stern-plane
/// deflection [rad]:
///   delta = K_p * (d_cmd - d) + K_d * (d_dot_cmd - d_dot)
/// clamped to [-delta_max, +delta_max].
pub fn pdControlLawRad(
    K_p: f64,
    K_d: f64,
    d_cmd_m: f64,
    d_actual_m: f64,
    d_dot_cmd_mps: f64,
    d_dot_actual_mps: f64,
    delta_max_rad: f64,
) Error!f64 {
    if (!(K_p > 0)) return Error.NonPositiveGain;
    if (!(K_d >= 0)) return Error.NonPositiveGain;
    if (!(delta_max_rad > 0 and delta_max_rad < std.math.pi / 2.0)) return Error.InvalidLimit;
    const e = d_cmd_m - d_actual_m;
    const e_dot = d_dot_cmd_mps - d_dot_actual_mps;
    var delta = K_p * e + K_d * e_dot;
    if (delta > delta_max_rad) delta = delta_max_rad;
    if (delta < -delta_max_rad) delta = -delta_max_rad;
    return delta;
}

/// Steady-state vertical velocity given a stern-plane angle delta
/// and forward speed V on a torpedo-shaped AUV. Simplified:
///   d_dot_ss = K_steady * delta * V
/// where K_steady ~ 1.0 for a well-balanced AUV with sufficient
/// pitch damping.
pub fn steadyStateVerticalVelocityMPerS(
    delta_rad: f64,
    V_mps: f64,
    K_steady: f64,
) Error!f64 {
    if (!(V_mps > 0)) return Error.NonPositiveDepth;
    if (!(K_steady > 0)) return Error.NonPositiveGain;
    return K_steady * delta_rad * V_mps;
}

/// Depth-error first-order time constant for a PD controller:
///   tau ~ 1 / (K_p V K_steady).
pub fn depthErrorTimeConstantS(
    K_p: f64,
    V_mps: f64,
    K_steady: f64,
) Error!f64 {
    if (!(K_p > 0)) return Error.NonPositiveGain;
    if (!(V_mps > 0)) return Error.NonPositiveDepth;
    if (!(K_steady > 0)) return Error.NonPositiveGain;
    return 1.0 / (K_p * V_mps * K_steady);
}

test "PD law: zero error gives zero deflection" {
    const delta = try pdControlLawRad(0.1, 0.05, 10.0, 10.0, 0.0, 0.0, 0.3);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), delta, 1e-12);
}

test "PD law: positive depth error commands positive delta (descend)" {
    const delta = try pdControlLawRad(0.1, 0.0, 12.0, 10.0, 0.0, 0.0, 0.3);
    try std.testing.expect(delta > 0);
}

test "PD law: negative depth error commands negative delta (ascend)" {
    const delta = try pdControlLawRad(0.1, 0.0, 8.0, 10.0, 0.0, 0.0, 0.3);
    try std.testing.expect(delta < 0);
}

test "PD law clamps at delta_max" {
    const delta = try pdControlLawRad(1.0, 0.0, 100.0, 0.0, 0.0, 0.0, 0.3);
    try std.testing.expectApproxEqAbs(@as(f64, 0.3), delta, 1e-12);
}

test "PD law clamps at -delta_max" {
    const delta = try pdControlLawRad(1.0, 0.0, -100.0, 0.0, 0.0, 0.0, 0.3);
    try std.testing.expectApproxEqAbs(@as(f64, -0.3), delta, 1e-12);
}

test "PD law: D term opposes high descent rate" {
    // d_cmd = 10, d = 10 (zero error) but d_dot = +1 m/s (descending fast).
    // K_d term should command an ascent (negative delta).
    const delta = try pdControlLawRad(0.001, 0.5, 10.0, 10.0, 0.0, 1.0, 0.3);
    try std.testing.expect(delta < 0);
}

test "steady vertical velocity at delta=0.1 rad, V=2 m/s, K=1.0" {
    const v = try steadyStateVerticalVelocityMPerS(0.1, 2.0, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), v, 1e-12);
}

test "steady vertical velocity scales with V" {
    const v1 = try steadyStateVerticalVelocityMPerS(0.1, 1.0, 1.0);
    const v2 = try steadyStateVerticalVelocityMPerS(0.1, 2.0, 1.0);
    try std.testing.expectApproxEqAbs(2.0, v2 / v1, 1e-12);
}

test "time constant: K_p=0.1, V=2, K=1 -> 5 s" {
    const tau = try depthErrorTimeConstantS(0.1, 2.0, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), tau, 1e-12);
}

test "time constant inversely proportional to K_p" {
    const t1 = try depthErrorTimeConstantS(0.1, 2.0, 1.0);
    const t2 = try depthErrorTimeConstantS(0.2, 2.0, 1.0);
    try std.testing.expectApproxEqAbs(0.5, t2 / t1, 1e-9);
}

test "input rejection: zero K_p" {
    try std.testing.expectError(
        Error.NonPositiveGain,
        pdControlLawRad(0.0, 0.05, 10.0, 9.0, 0.0, 0.0, 0.3),
    );
}

test "input rejection: delta_max >= pi/2" {
    try std.testing.expectError(
        Error.InvalidLimit,
        pdControlLawRad(0.1, 0.05, 10.0, 9.0, 0.0, 0.0, 2.0),
    );
}
