const std = @import("std");

pub const Error = error{
    NonPositiveSpeed,
    NonPositiveThrust,
    NegativeResistance,
    InvalidThrustDeduction,
};

/// Inputs from a single self-propulsion test point at the ship self-
/// propulsion operating point (SOP).
pub const SOPInputs = struct {
    /// Towed resistance at the same model speed [N].
    R_T_model_n: f64,
    /// Measured thrust at SOP (after applying the self-propulsion
    /// frictional correction F_D) [N].
    T_model_n: f64,
    /// Model speed of advance V_m [m/s].
    V_m: f64,
    /// Measured advance velocity V_a [m/s] from open-water thrust
    /// identity (caller pre-computed via K_T-J coupling).
    V_a: f64,
};

/// Thrust-deduction factor t = 1 - R_T / T.
pub fn thrustDeductionFactor(R_T_n: f64, T_n: f64) Error!f64 {
    if (!(R_T_n >= 0)) return Error.NegativeResistance;
    if (!(T_n > 0)) return Error.NonPositiveThrust;
    return 1.0 - R_T_n / T_n;
}

/// Wake fraction w_T = 1 - V_a / V_m (Taylor formulation).
pub fn taylorWakeFraction(V_m: f64, V_a: f64) Error!f64 {
    if (!(V_m > 0)) return Error.NonPositiveSpeed;
    if (!(V_a > 0)) return Error.NonPositiveSpeed;
    return 1.0 - V_a / V_m;
}

/// Hull efficiency eta_H = (1 - t) / (1 - w_T).
pub fn hullEfficiency(t: f64, w_T: f64) Error!f64 {
    if (!(t < 1.0)) return Error.InvalidThrustDeduction;
    if (!(w_T < 1.0)) return Error.NonPositiveSpeed;
    return (1.0 - t) / (1.0 - w_T);
}

/// Full SOP extraction packed into a Result struct.
pub const SOPResult = struct {
    t: f64,
    w_T: f64,
    eta_H: f64,
};

pub fn analyzeSOP(in: SOPInputs) Error!SOPResult {
    const t = try thrustDeductionFactor(in.R_T_model_n, in.T_model_n);
    const w_T = try taylorWakeFraction(in.V_m, in.V_a);
    const eta_H = try hullEfficiency(t, w_T);
    return .{ .t = t, .w_T = w_T, .eta_H = eta_H };
}

test "thrust-deduction factor t = 1 - R_T / T" {
    const t = try thrustDeductionFactor(800.0, 1000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), t, 1e-12);
}

test "thrust-deduction zero resistance gives t = 1" {
    const t = try thrustDeductionFactor(0.0, 1000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), t, 1e-12);
}

test "thrust-deduction R = T gives t = 0" {
    const t = try thrustDeductionFactor(1000.0, 1000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), t, 1e-12);
}

test "thrust-deduction rejects non-positive thrust" {
    try std.testing.expectError(Error.NonPositiveThrust, thrustDeductionFactor(100.0, 0.0));
    try std.testing.expectError(Error.NonPositiveThrust, thrustDeductionFactor(100.0, -50.0));
}

test "thrust-deduction rejects negative resistance" {
    try std.testing.expectError(Error.NegativeResistance, thrustDeductionFactor(-5.0, 100.0));
}

test "Taylor wake fraction w = 1 - V_a / V_m" {
    const w = try taylorWakeFraction(2.0, 1.4);
    try std.testing.expectApproxEqAbs(@as(f64, 0.3), w, 1e-12);
}

test "Taylor wake fraction rejects non-positive speeds" {
    try std.testing.expectError(Error.NonPositiveSpeed, taylorWakeFraction(0.0, 1.0));
    try std.testing.expectError(Error.NonPositiveSpeed, taylorWakeFraction(2.0, 0.0));
}

test "hull efficiency eta_H = (1 - t) / (1 - w)" {
    const eta = try hullEfficiency(0.2, 0.3);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8 / 0.7), eta, 1e-12);
    // Typical ship eta_H is around 1.0 - 1.2.
    try std.testing.expect(eta > 1.0 and eta < 1.5);
}

test "hull efficiency rejects t >= 1" {
    try std.testing.expectError(Error.InvalidThrustDeduction, hullEfficiency(1.0, 0.3));
}

test "analyzeSOP composes the three steps" {
    const in: SOPInputs = .{
        .R_T_model_n = 800.0,
        .T_model_n = 1000.0,
        .V_m = 2.0,
        .V_a = 1.4,
    };
    const r = try analyzeSOP(in);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), r.t, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.3), r.w_T, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8 / 0.7), r.eta_H, 1e-12);
}

test "analyzeSOP V_a > V_m yields negative wake (Hovgaard regime allowed numerically)" {
    // Some fast craft show V_a > V_m. The kernel returns a negative
    // wake fraction; eta_H exceeds (1 - t) numerically.
    const in: SOPInputs = .{
        .R_T_model_n = 500.0,
        .T_model_n = 1000.0,
        .V_m = 5.0,
        .V_a = 5.5,
    };
    const r = try analyzeSOP(in);
    try std.testing.expect(r.w_T < 0.0);
    try std.testing.expect(r.eta_H < 1.0 - r.t);
}
