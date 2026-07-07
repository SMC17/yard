const std = @import("std");

pub const Error = error{
    NonPositiveDraft,
    NonPositiveSpeed,
    NonPositiveLength,
    InvalidUKC,
};

/// PIANC under-keel-clearance recommendation as a fraction of T:
///   exposed approach: UKC ~ 0.20 T (often 1.5 m absolute min);
///   inner channel:    UKC ~ 0.10 T;
///   docks:            UKC ~ 0.05 T.
pub const UkcLevel = enum {
    exposed,
    inner_channel,
    dock,

    pub fn fractionOfT(self: UkcLevel) f64 {
        return switch (self) {
            .exposed => 0.20,
            .inner_channel => 0.10,
            .dock => 0.05,
        };
    }
};

/// Required UKC [m] from PIANC fraction, with a minimum floor.
pub fn requiredUKCM(T_m: f64, level: UkcLevel, ukc_floor_m: f64) Error!f64 {
    if (!(T_m > 0)) return Error.NonPositiveDraft;
    if (!(ukc_floor_m >= 0)) return Error.InvalidUKC;
    const ukc = T_m * level.fractionOfT();
    if (ukc < ukc_floor_m) return ukc_floor_m;
    return ukc;
}

/// Squat (bow sinkage) per Barrass 1979 simplified formula:
///   s_max = C_B V^2.08 / (30 K)
/// with V in knots, C_B block coefficient, and K a channel-width
/// factor (~ 0.5 for restricted; ~ 1.0 for open channel).
pub fn squatBarrassM(
    C_B: f64,
    V_knots: f64,
    K_channel: f64,
) Error!f64 {
    if (!(C_B > 0 and C_B <= 1.0)) return Error.NonPositiveDraft;
    if (!(V_knots > 0)) return Error.NonPositiveSpeed;
    if (!(K_channel > 0)) return Error.NonPositiveLength;
    return C_B * std.math.pow(f64, V_knots, 2.08) / (30.0 * K_channel);
}

/// Gross channel depth:
///   d_gross = T + UKC + squat + heave_pitch_envelope + safety_margin.
pub fn grossChannelDepthM(
    T_m: f64,
    ukc_m: f64,
    squat_m: f64,
    heave_pitch_m: f64,
    safety_m: f64,
) Error!f64 {
    if (!(T_m > 0)) return Error.NonPositiveDraft;
    if (!(ukc_m >= 0)) return Error.InvalidUKC;
    if (!(squat_m >= 0)) return Error.InvalidUKC;
    if (!(heave_pitch_m >= 0)) return Error.InvalidUKC;
    if (!(safety_m >= 0)) return Error.InvalidUKC;
    return T_m + ukc_m + squat_m + heave_pitch_m + safety_m;
}

/// PIANC two-way channel width:
///   W_two_way = 2 W_basic + W_bank_clearance.
/// W_basic depends on manoeuvring difficulty; the kernel exposes a
/// minimum-width estimator based on ship beam:
///   W_basic ~ 1.8 B (good manoeuvrability)
///          ~ 2.0 B (moderate)
///          ~ 2.5 B (difficult).
pub const ManoeuvringClass = enum {
    good,
    moderate,
    difficult,

    pub fn basicWidthFactor(self: ManoeuvringClass) f64 {
        return switch (self) {
            .good => 1.8,
            .moderate => 2.0,
            .difficult => 2.5,
        };
    }
};

pub fn twoWayChannelWidthM(
    B_m: f64,
    cls: ManoeuvringClass,
    bank_clearance_m: f64,
) Error!f64 {
    if (!(B_m > 0)) return Error.NonPositiveLength;
    if (!(bank_clearance_m >= 0)) return Error.InvalidUKC;
    return 2.0 * cls.basicWidthFactor() * B_m + bank_clearance_m;
}

test "UKC exposed 0.20 T at T=15 m gives 3 m" {
    const u = try requiredUKCM(15.0, .exposed, 1.5);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), u, 1e-12);
}

test "UKC dock 0.05 T below floor returns floor" {
    const u = try requiredUKCM(10.0, .dock, 1.0);
    // 0.05 * 10 = 0.5 < 1.0 -> floor.
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), u, 1e-12);
}

test "UKC level ordering: exposed > inner > dock" {
    try std.testing.expect(UkcLevel.exposed.fractionOfT() > UkcLevel.inner_channel.fractionOfT());
    try std.testing.expect(UkcLevel.inner_channel.fractionOfT() > UkcLevel.dock.fractionOfT());
}

test "Barrass squat at C_B = 0.8, V = 10 kt, K = 1.0" {
    const s = try squatBarrassM(0.8, 10.0, 1.0);
    const expected = 0.8 * std.math.pow(f64, 10.0, 2.08) / 30.0;
    try std.testing.expectApproxEqAbs(expected, s, 1e-9);
}

test "squat doubles when K halves (restricted channel)" {
    const s_open = try squatBarrassM(0.8, 10.0, 1.0);
    const s_restricted = try squatBarrassM(0.8, 10.0, 0.5);
    try std.testing.expectApproxEqAbs(2.0 * s_open, s_restricted, 1e-9);
}

test "squat scales with V^2.08" {
    const s_5 = try squatBarrassM(0.8, 5.0, 1.0);
    const s_10 = try squatBarrassM(0.8, 10.0, 1.0);
    const expected_ratio = std.math.pow(f64, 2.0, 2.08);
    try std.testing.expectApproxEqAbs(expected_ratio, s_10 / s_5, 1e-9);
}

test "gross depth: T + UKC + squat + heave + safety" {
    const d = try grossChannelDepthM(15.0, 3.0, 0.5, 1.0, 0.5);
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), d, 1e-12);
}

test "manoeuvring class width factors" {
    try std.testing.expectApproxEqAbs(@as(f64, 1.8), ManoeuvringClass.good.basicWidthFactor(), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), ManoeuvringClass.difficult.basicWidthFactor(), 1e-12);
}

test "two-way channel width: B=40, moderate, 20 m bank clearance" {
    const W = try twoWayChannelWidthM(40.0, .moderate, 20.0);
    // 2 * 2.0 * 40 + 20 = 180 m.
    try std.testing.expectApproxEqAbs(@as(f64, 180.0), W, 1e-9);
}

test "two-way width scales linearly with B" {
    const W1 = try twoWayChannelWidthM(40.0, .moderate, 20.0);
    const W2 = try twoWayChannelWidthM(80.0, .moderate, 20.0);
    // Bank clearance constant; 2 * 2 * 80 + 20 = 340 vs 2 * 2 * 40 + 20 = 180.
    // Difference = 160 = 2 * 80; ratio not exactly 2 because of bank clearance.
    try std.testing.expect(W2 > W1);
    try std.testing.expect(W2 < 2.0 * W1);
}

test "input rejection: zero T" {
    try std.testing.expectError(Error.NonPositiveDraft, requiredUKCM(0.0, .exposed, 1.5));
}

test "input rejection: zero K channel" {
    try std.testing.expectError(Error.NonPositiveLength, squatBarrassM(0.8, 10.0, 0.0));
}

test "input rejection: zero V" {
    try std.testing.expectError(Error.NonPositiveSpeed, squatBarrassM(0.8, 0.0, 1.0));
}

test "input rejection: zero B in channel width" {
    try std.testing.expectError(Error.NonPositiveLength, twoWayChannelWidthM(0.0, .moderate, 20.0));
}
