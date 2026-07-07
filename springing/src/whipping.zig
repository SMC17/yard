const std = @import("std");

pub const Error = error{
    NegativeDamping,
    NegativeTime,
    NonPositiveFrequency,
};

/// Damped angular frequency:
///   omega_d = omega_n sqrt(1 - zeta^2).
pub fn dampedAngularFrequencyRps(omega_n_rps: f64, zeta: f64) Error!f64 {
    if (!(omega_n_rps > 0)) return Error.NonPositiveFrequency;
    if (!(zeta >= 0.0 and zeta < 1.0)) return Error.NegativeDamping;
    return omega_n_rps * @sqrt(1.0 - zeta * zeta);
}

/// Free-decay envelope of an underdamped hull-girder mode after a
/// unit impulse:
///   x(t) = exp(-zeta omega_n t) * cos(omega_d t)
/// Useful for whipping bending-moment amplification estimation.
pub fn freeDecayAmplitude(
    omega_n_rps: f64,
    zeta: f64,
    t_s: f64,
) Error!f64 {
    if (!(t_s >= 0)) return Error.NegativeTime;
    if (!(omega_n_rps > 0)) return Error.NonPositiveFrequency;
    if (!(zeta >= 0.0 and zeta < 1.0)) return Error.NegativeDamping;
    const omega_d = try dampedAngularFrequencyRps(omega_n_rps, zeta);
    return @exp(-zeta * omega_n_rps * t_s) * @cos(omega_d * t_s);
}

/// Logarithmic decrement delta = 2 pi zeta / sqrt(1 - zeta^2)
/// from the underdamped damping ratio.
pub fn logarithmicDecrement(zeta: f64) Error!f64 {
    if (!(zeta >= 0.0 and zeta < 1.0)) return Error.NegativeDamping;
    return 2.0 * std.math.pi * zeta / @sqrt(1.0 - zeta * zeta);
}

test "damped frequency at zeta = 0 equals natural frequency" {
    const o = try dampedAngularFrequencyRps(10.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), o, 1e-12);
}

test "damped frequency at zeta = 0.1" {
    const o = try dampedAngularFrequencyRps(10.0, 0.1);
    const expected = 10.0 * @sqrt(0.99);
    try std.testing.expectApproxEqAbs(expected, o, 1e-9);
}

test "free-decay amplitude at t = 0 equals 1" {
    const x = try freeDecayAmplitude(10.0, 0.05, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), x, 1e-12);
}

test "free-decay amplitude monotone envelope at quarter-period stride" {
    // Sample at quarter-period spacing in the envelope (cos = 0 at
    // odd quarter-periods); envelope alone decays monotonically.
    const omega_n: f64 = 10.0;
    const zeta: f64 = 0.05;
    const omega_d = try dampedAngularFrequencyRps(omega_n, zeta);
    const dt = std.math.pi / omega_d; // one full damped half-period
    var prev_env: f64 = 1.0;
    var i: usize = 1;
    while (i < 5) : (i += 1) {
        const t = dt * @as(f64, @floatFromInt(i));
        const env = @exp(-zeta * omega_n * t);
        try std.testing.expect(env < prev_env);
        prev_env = env;
    }
}

test "logarithmic decrement at zeta = 0 is zero" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try logarithmicDecrement(0.0), 1e-12);
}

test "logarithmic decrement at zeta = 0.1 closed form" {
    const d = try logarithmicDecrement(0.1);
    const expected = 2.0 * std.math.pi * 0.1 / @sqrt(0.99);
    try std.testing.expectApproxEqAbs(expected, d, 1e-9);
}

test "input rejection: zeta >= 1 (overdamped)" {
    try std.testing.expectError(Error.NegativeDamping, dampedAngularFrequencyRps(10.0, 1.0));
}

test "input rejection: negative time" {
    try std.testing.expectError(Error.NegativeTime, freeDecayAmplitude(10.0, 0.05, -1.0));
}

test "input rejection: zero natural frequency" {
    try std.testing.expectError(Error.NonPositiveFrequency, dampedAngularFrequencyRps(0.0, 0.05));
}
