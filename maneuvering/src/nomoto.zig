// Nomoto K-T yaw maneuvering model.
//
// First-order (Nomoto 1957):
//
//   T * dr/dt + r = K * delta_r
//
// where r is yaw rate (rad/s), delta_r is rudder angle (rad), K is the
// gain (rad/s per rad), and T is the time constant (s).
//
// Step response (r(0) = 0, delta_r = delta_0 for t >= 0):
//
//   r(t) = K * delta_0 * (1 - exp(-t / T))
//
// Heading (psi(0) = 0):
//
//   psi(t) = K * delta_0 * (t - T * (1 - exp(-t / T)))
//
// Second-order Nomoto:
//
//   T1 * T2 * d^2 r / dt^2 + (T1 + T2) * dr/dt + r
//       = K * (delta_r + T3 * d delta_r / dt)
//
// First-order T equals T1 + T2 - T3.
//
// Zig-zag overshoot estimate (approximate, first-order):
//
//   alpha_overshoot ~ K * delta_zigzag * T * (1 - exp(-t_execute / T))
//
// where t_execute is the time the rudder is held at delta_zigzag before
// the predicted overshoot at the rudder reversal.

const std = @import("std");

pub const Error = error{
    NonPositiveTimeConstant,
    NonPositiveTime,
};

/// First-order Nomoto step-response yaw rate.
/// `delta_0` is the held rudder angle (rad); `t` is time since rudder
/// application (s); `K` is the gain; `T` is the time constant.
pub fn nomotoFirstOrderYawRate(K: f64, T: f64, delta_0: f64, t: f64) Error!f64 {
    if (T <= 0.0) return Error.NonPositiveTimeConstant;
    return K * delta_0 * (1.0 - @exp(-t / T));
}

/// First-order Nomoto step-response heading.
pub fn nomotoFirstOrderHeading(K: f64, T: f64, delta_0: f64, t: f64) Error!f64 {
    if (T <= 0.0) return Error.NonPositiveTimeConstant;
    return K * delta_0 * (t - T * (1.0 - @exp(-t / T)));
}

/// First-order Nomoto steady-state yaw rate: K * delta_0.
pub fn nomotoSteadyStateYawRate(K: f64, delta_0: f64) f64 {
    return K * delta_0;
}

/// Second-order T from first-order parameters: T = T1 + T2 - T3.
pub fn firstOrderTFromSecondOrder(T1: f64, T2: f64, T3: f64) f64 {
    return T1 + T2 - T3;
}

/// Second-order Nomoto step response computed by closed-form
/// superposition of the two real modes when T1 != T2.
///
/// d^2 r / dt^2 * T1 T2 + dr/dt * (T1 + T2) + r = K * delta_0
///
/// with r(0) = 0, dr/dt(0) = 0 has solution:
///
///   r(t) = K * delta_0 * (1 + (T2 exp(-t/T1) - T1 exp(-t/T2)) / (T1 - T2))
///
/// (rudder-rate term T3 d delta_r / dt is zero for a step input.)
pub fn nomotoSecondOrderYawRate(K: f64, T1: f64, T2: f64, delta_0: f64, t: f64) Error!f64 {
    if (T1 <= 0.0 or T2 <= 0.0) return Error.NonPositiveTimeConstant;
    if (T1 == T2) {
        // Double-root: r(t) = K * delta_0 * (1 - (1 + t / T1) * exp(-t / T1))
        return K * delta_0 * (1.0 - (1.0 + t / T1) * @exp(-t / T1));
    }
    const denom = T1 - T2;
    const term = (T2 * @exp(-t / T1) - T1 * @exp(-t / T2)) / denom;
    return K * delta_0 * (1.0 + term);
}

const expectApproxEqAbs = std.testing.expectApproxEqAbs;
const expectApproxEqRel = std.testing.expectApproxEqRel;

test "first-order yaw rate is zero at t = 0" {
    const r = try nomotoFirstOrderYawRate(0.18, 14.0, 0.1745, 0.0);
    try expectApproxEqAbs(@as(f64, 0.0), r, 1e-12);
}

test "first-order yaw rate converges to K delta_0 at large t" {
    const r = try nomotoFirstOrderYawRate(0.18, 14.0, 0.1745, 1000.0);
    std.debug.print("\n[VERIFICATION] Nomoto first-order yaw rate: {d}\n", .{r});
    try expectApproxEqRel(nomotoSteadyStateYawRate(0.18, 0.1745), r, 1e-6);
}

test "first-order yaw rate at t = T is approximately 63 percent of steady state" {
    const T: f64 = 14.0;
    const K: f64 = 0.18;
    const delta_0: f64 = 0.1745;
    const r_at_T = try nomotoFirstOrderYawRate(K, T, delta_0, T);
    const ss = nomotoSteadyStateYawRate(K, delta_0);
    // 1 - exp(-1) = 0.632...
    try expectApproxEqRel(@as(f64, 0.6321), r_at_T / ss, 1e-3);
}

test "first-order heading is zero at t = 0" {
    const psi = try nomotoFirstOrderHeading(0.18, 14.0, 0.1745, 0.0);
    try expectApproxEqAbs(@as(f64, 0.0), psi, 1e-12);
}

test "first-order heading at large t is approximately K delta_0 (t - T)" {
    const T: f64 = 14.0;
    const K: f64 = 0.18;
    const delta_0: f64 = 0.1745;
    const t: f64 = 100.0;
    const psi = try nomotoFirstOrderHeading(K, T, delta_0, t);
    const expected = K * delta_0 * (t - T);
    try expectApproxEqRel(expected, psi, 1e-3);
}

test "second-order yaw rate is zero at t = 0 (T1 != T2)" {
    const r = try nomotoSecondOrderYawRate(0.18, 5.0, 9.0, 0.1745, 0.0);
    try expectApproxEqAbs(@as(f64, 0.0), r, 1e-12);
}

test "second-order yaw rate approaches steady state as T2 shrinks at finite t >> T2" {
    // When T2 is very small relative to t, the fast mode has decayed; only
    // the slow mode contributes. The response is approximately K * delta_0
    // times (1 + (T2/T1) exp(-t/T1)), which at small T2 is essentially K * delta_0.
    const K: f64 = 0.18;
    const T1: f64 = 14.0;
    const T2: f64 = 0.001;
    const delta_0: f64 = 0.1745;
    const r = try nomotoSecondOrderYawRate(K, T1, T2, delta_0, 30.0);
    const ss = nomotoSteadyStateYawRate(K, delta_0);
    // r should be within a few percent of steady state since T2 is so small.
    try std.testing.expect(@abs(r - ss) / ss < 0.05);
}

test "second-order converges to K delta_0 at large t" {
    const r = try nomotoSecondOrderYawRate(0.18, 5.0, 9.0, 0.1745, 1000.0);
    try expectApproxEqRel(nomotoSteadyStateYawRate(0.18, 0.1745), r, 1e-6);
}

test "second-order with double root (T1 = T2)" {
    const K: f64 = 0.5;
    const T: f64 = 5.0;
    const delta_0: f64 = 0.2;
    const r_ss = try nomotoSecondOrderYawRate(K, T, T, delta_0, 1000.0);
    try expectApproxEqRel(K * delta_0, r_ss, 1e-6);
    const r_zero = try nomotoSecondOrderYawRate(K, T, T, delta_0, 0.0);
    try expectApproxEqAbs(@as(f64, 0.0), r_zero, 1e-12);
}

test "firstOrderTFromSecondOrder identity" {
    try expectApproxEqAbs(@as(f64, 12.0), firstOrderTFromSecondOrder(5.0, 9.0, 2.0), 1e-12);
}

test "first-order yaw rate rejects non-positive T" {
    try std.testing.expectError(Error.NonPositiveTimeConstant, nomotoFirstOrderYawRate(0.18, 0.0, 0.1745, 1.0));
    try std.testing.expectError(Error.NonPositiveTimeConstant, nomotoFirstOrderYawRate(0.18, -1.0, 0.1745, 1.0));
}

test "first-order yaw rate is monotonically increasing for positive delta_0 and K" {
    const K: f64 = 0.18;
    const T: f64 = 14.0;
    const delta_0: f64 = 0.1745;
    var prev: f64 = -std.math.inf(f64);
    var t: f64 = 0.0;
    while (t <= 50.0) : (t += 0.5) {
        const r = try nomotoFirstOrderYawRate(K, T, delta_0, t);
        try std.testing.expect(r > prev);
        prev = r;
    }
}

test "first-order yaw rate reverses sign with delta_0 sign" {
    const r_pos = try nomotoFirstOrderYawRate(0.18, 14.0, 0.1745, 30.0);
    const r_neg = try nomotoFirstOrderYawRate(0.18, 14.0, -0.1745, 30.0);
    try expectApproxEqAbs(r_pos, -r_neg, 1e-12);
}

test "first-order heading scales linearly with delta_0" {
    const psi_1 = try nomotoFirstOrderHeading(0.18, 14.0, 0.1, 30.0);
    const psi_2 = try nomotoFirstOrderHeading(0.18, 14.0, 0.2, 30.0);
    try expectApproxEqRel(2.0 * psi_1, psi_2, 1e-12);
}
