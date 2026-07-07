const std = @import("std");

pub const Error = error{
    NonPositiveLoad,
    NonPositiveGravity,
    NegativeAcceleration,
};

/// Dynamic Amplification Factor for a crane load on a moving deck.
/// Per DNV-OS-C201 / IACS Rec. 38 the SWL must be derated for the
/// vertical acceleration at the crane tip:
///   DAF = 1 + a_v / g
/// where a_v is the vertical acceleration at the crane-tip position.
/// Returns 1 at zero a_v; greater than 1 for upward acceleration.
pub fn dynamicAmplificationFactor(a_v_mps2: f64, g_mps2: f64) Error!f64 {
    if (!(g_mps2 > 0)) return Error.NonPositiveGravity;
    return 1.0 + a_v_mps2 / g_mps2;
}

/// Effective dynamic load:
///   F_dyn = SWL * g * DAF.
pub fn dynamicLoadN(SWL_t: f64, a_v_mps2: f64, g_mps2: f64) Error!f64 {
    if (!(SWL_t > 0)) return Error.NonPositiveLoad;
    const DAF = try dynamicAmplificationFactor(a_v_mps2, g_mps2);
    return SWL_t * 1000.0 * g_mps2 * DAF;
}

/// Vertical-acceleration envelope per Hs significant wave height
/// (DNV-RP-N103 indicative values for an offshore crane vessel):
///   a_v = 1.2 * Hs / T_z^2 ~ 0.5-3.0 m/s^2 typical.
pub fn waveDrivenAccelerationMPS2(Hs_m: f64, T_z_s: f64) Error!f64 {
    if (!(Hs_m > 0)) return Error.NonPositiveLoad;
    if (!(T_z_s > 0)) return Error.NonPositiveGravity;
    return 1.2 * Hs_m / (T_z_s * T_z_s);
}

/// SWL derating: reduce the static SWL by the DAF so the dynamic
/// load matches the original static SWL.
pub fn deratedSWL(SWL_static_t: f64, a_v_mps2: f64, g_mps2: f64) Error!f64 {
    if (!(SWL_static_t > 0)) return Error.NonPositiveLoad;
    const DAF = try dynamicAmplificationFactor(a_v_mps2, g_mps2);
    if (DAF <= 0.0) return Error.NegativeAcceleration;
    return SWL_static_t / DAF;
}

test "DAF at a_v = 0 equals 1" {
    const d = try dynamicAmplificationFactor(0.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), d, 1e-12);
}

test "DAF at a_v = g equals 2" {
    const d = try dynamicAmplificationFactor(9.81, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), d, 1e-12);
}

test "DAF at a_v = -g/2 equals 0.5" {
    const d = try dynamicAmplificationFactor(-4.905, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), d, 1e-9);
}

test "dynamic load: 50 t SWL at a_v = 2 m/s^2" {
    const F = try dynamicLoadN(50.0, 2.0, 9.81);
    // DAF = 1 + 2 / 9.81 = 1.2039. F = 50000 * 9.81 * 1.2039 = 590 491 N.
    const expected = 50.0 * 1000.0 * 9.81 * (1.0 + 2.0 / 9.81);
    try std.testing.expectApproxEqAbs(expected, F, 1e-6);
}

test "wave-driven acceleration at Hs=4 m, T_z=8 s" {
    const a = try waveDrivenAccelerationMPS2(4.0, 8.0);
    const expected = 1.2 * 4.0 / (8.0 * 8.0);
    try std.testing.expectApproxEqAbs(expected, a, 1e-12);
}

test "wave-driven acceleration scales with Hs / T_z^2" {
    const a1 = try waveDrivenAccelerationMPS2(2.0, 8.0);
    const a2 = try waveDrivenAccelerationMPS2(4.0, 8.0);
    try std.testing.expectApproxEqAbs(2.0 * a1, a2, 1e-12);
    const a3 = try waveDrivenAccelerationMPS2(4.0, 16.0);
    try std.testing.expectApproxEqAbs(a2 / 4.0, a3, 1e-12);
}

test "derated SWL at a_v = g gives half the static SWL" {
    const d = try deratedSWL(50.0, 9.81, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 25.0), d, 1e-9);
}

test "derated SWL at a_v = 0 equals static SWL" {
    const d = try deratedSWL(50.0, 0.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), d, 1e-9);
}

test "input rejection: zero g" {
    try std.testing.expectError(
        Error.NonPositiveGravity,
        dynamicAmplificationFactor(2.0, 0.0),
    );
}

test "input rejection: zero SWL" {
    try std.testing.expectError(Error.NonPositiveLoad, dynamicLoadN(0.0, 2.0, 9.81));
}

test "input rejection: zero T_z" {
    try std.testing.expectError(
        Error.NonPositiveGravity,
        waveDrivenAccelerationMPS2(4.0, 0.0),
    );
}
