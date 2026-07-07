const std = @import("std");

pub const Error = error{
    NonPositivePower,
    InvalidCoefficient,
};

pub const TugType = enum {
    /// Conventional twin-screw harbour tug.
    Conventional,
    /// Z-drive azimuthing stern-drive (ASD).
    ASD,
    /// Tractor / Voith Schneider Propeller (VSP) tug.
    VSP,
    /// Escort tug with high-skeg hull.
    Escort,

    /// Bollard-pull coefficient in kN per kW of brake power
    /// (Carlton 2018 + manufacturer rules of thumb).
    pub fn bollardCoefficient(self: TugType) f64 {
        return switch (self) {
            .Conventional => 0.10,
            .ASD => 0.12,
            .VSP => 0.13,
            .Escort => 0.135,
        };
    }
};

/// Static bollard pull from brake power:
///   BP [kN] = k_BP * P_brake [kW].
pub fn bollardPullKN(P_brake_kw: f64, ttype: TugType) Error!f64 {
    if (!(P_brake_kw > 0)) return Error.NonPositivePower;
    return ttype.bollardCoefficient() * P_brake_kw;
}

/// Bollard pull from a custom coefficient.
pub fn bollardPullCustomKN(P_brake_kw: f64, k_bp: f64) Error!f64 {
    if (!(P_brake_kw > 0)) return Error.NonPositivePower;
    if (!(k_bp > 0)) return Error.InvalidCoefficient;
    return k_bp * P_brake_kw;
}

/// Convert bollard pull from kN to tonnes-force:
///   BP_t = BP_kN / g_kn_per_t  (with g_kn_per_t = 9.80665).
pub fn bollardPullToTonnesForce(BP_kN: f64) f64 {
    return BP_kN / 9.80665;
}

/// Equivalent thrust-to-weight ratio for a tug of mass m_tug:
///   T_w = BP / (m_tug g).
pub fn thrustToWeightRatio(BP_kN: f64, m_tug_t: f64) Error!f64 {
    if (!(m_tug_t > 0)) return Error.NonPositivePower;
    return BP_kN / (m_tug_t * 9.80665);
}

test "conventional tug at 2000 kW yields 200 kN" {
    const BP = try bollardPullKN(2000.0, .Conventional);
    try std.testing.expectApproxEqAbs(@as(f64, 200.0), BP, 1e-9);
}

test "ASD tug at 2000 kW yields 240 kN" {
    const BP = try bollardPullKN(2000.0, .ASD);
    try std.testing.expectApproxEqAbs(@as(f64, 240.0), BP, 1e-9);
}

test "VSP tug at 2000 kW yields 260 kN" {
    const BP = try bollardPullKN(2000.0, .VSP);
    try std.testing.expectApproxEqAbs(@as(f64, 260.0), BP, 1e-9);
}

test "Escort tug exceeds ASD coefficient" {
    try std.testing.expect(TugType.Escort.bollardCoefficient() >
        TugType.ASD.bollardCoefficient());
}

test "bollard pull scales linearly with power" {
    const BP1 = try bollardPullKN(1000.0, .ASD);
    const BP2 = try bollardPullKN(2000.0, .ASD);
    try std.testing.expectApproxEqAbs(2.0 * BP1, BP2, 1e-9);
}

test "custom coefficient bollard pull" {
    const BP = try bollardPullCustomKN(3000.0, 0.115);
    try std.testing.expectApproxEqAbs(@as(f64, 345.0), BP, 1e-9);
}

test "tonnes-force conversion: 240 kN = 24.47 tf" {
    const tf = bollardPullToTonnesForce(240.0);
    try std.testing.expectApproxEqAbs(@as(f64, 240.0 / 9.80665), tf, 1e-9);
}

test "thrust-to-weight at 240 kN BP and 300 t tug" {
    const tw = try thrustToWeightRatio(240.0, 300.0);
    const expected = 240.0 / (300.0 * 9.80665);
    try std.testing.expectApproxEqAbs(expected, tw, 1e-9);
}

test "input rejection: zero power" {
    try std.testing.expectError(Error.NonPositivePower, bollardPullKN(0.0, .ASD));
}

test "input rejection: zero custom coefficient" {
    try std.testing.expectError(Error.InvalidCoefficient, bollardPullCustomKN(1000.0, 0.0));
}
