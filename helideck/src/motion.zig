const std = @import("std");

pub const Error = error{
    NonPositiveDistance,
    NonPositiveAngle,
    NonPositiveVelocity,
    InvalidClass,
};

/// Helideck operating class per ICAO Annex 14 / CAP 437. Class 1
/// (largest helicopter, most stringent limits) through Class 3.
pub const HelideckClass = enum {
    /// Largest helicopter (e.g. EC225, S-92, AW189) - tightest limits.
    Class_1,
    /// Medium helicopter (e.g. EC155, AW139).
    Class_2,
    /// Small helicopter (e.g. AW109, BK117).
    Class_3,
};

pub const MotionLimits = struct {
    pitch_deg_max: f64,
    roll_deg_max: f64,
    inclination_deg_max: f64,
    heave_rate_mps_max: f64,
};

/// CAP 437 / MSC.1/Circ.1378 motion-limit table per helideck class.
/// Values reflect the commonly cited offshore-helideck envelope; the
/// authoritative source is CAP 437 Section 7 + the helicopter-
/// operator's individual MEL.
pub fn limitsForClass(cls: HelideckClass) MotionLimits {
    return switch (cls) {
        .Class_1 => .{
            .pitch_deg_max = 1.5,
            .roll_deg_max = 2.5,
            .inclination_deg_max = 2.0,
            .heave_rate_mps_max = 0.9,
        },
        .Class_2 => .{
            .pitch_deg_max = 2.5,
            .roll_deg_max = 4.0,
            .inclination_deg_max = 3.0,
            .heave_rate_mps_max = 1.3,
        },
        .Class_3 => .{
            .pitch_deg_max = 3.0,
            .roll_deg_max = 5.0,
            .inclination_deg_max = 4.0,
            .heave_rate_mps_max = 1.5,
        },
    };
}

/// Lateral acceleration at the deck CG resulting from roll motion at
/// rate phi_double_dot and lever arm h (helideck CG above ship's
/// roll axis):
///   a_y = phi_double_dot * h.
pub fn lateralAccelerationFromRollMPS2(
    phi_double_dot_rps2: f64,
    h_m: f64,
) Error!f64 {
    if (!(h_m > 0)) return Error.NonPositiveDistance;
    return phi_double_dot_rps2 * h_m;
}

/// Resulting inclination from combined pitch theta and roll phi:
///   beta = sqrt(theta^2 + phi^2)
/// (small-angle approximation).
pub fn inclinationDeg(pitch_deg: f64, roll_deg: f64) f64 {
    return @sqrt(pitch_deg * pitch_deg + roll_deg * roll_deg);
}

pub const Verdict = enum {
    /// All four limits satisfied.
    pass,
    /// At least one limit exceeded.
    fail,
};

/// Full operating envelope check.
pub fn envelopeVerdict(
    cls: HelideckClass,
    pitch_deg: f64,
    roll_deg: f64,
    heave_rate_mps: f64,
) Error!Verdict {
    if (!(pitch_deg >= 0)) return Error.NonPositiveAngle;
    if (!(roll_deg >= 0)) return Error.NonPositiveAngle;
    if (!(heave_rate_mps >= 0)) return Error.NonPositiveVelocity;
    const lim = limitsForClass(cls);
    if (pitch_deg > lim.pitch_deg_max) return .fail;
    if (roll_deg > lim.roll_deg_max) return .fail;
    if (heave_rate_mps > lim.heave_rate_mps_max) return .fail;
    if (inclinationDeg(pitch_deg, roll_deg) > lim.inclination_deg_max) return .fail;
    return .pass;
}

test "Class 1 limits: 1.5 / 2.5 / 2.0 / 0.9" {
    const l = limitsForClass(.Class_1);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), l.pitch_deg_max, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), l.roll_deg_max, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), l.inclination_deg_max, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.9), l.heave_rate_mps_max, 1e-12);
}

test "Class 3 limits exceed Class 1 in every dimension" {
    const l1 = limitsForClass(.Class_1);
    const l3 = limitsForClass(.Class_3);
    try std.testing.expect(l3.pitch_deg_max > l1.pitch_deg_max);
    try std.testing.expect(l3.roll_deg_max > l1.roll_deg_max);
    try std.testing.expect(l3.inclination_deg_max > l1.inclination_deg_max);
    try std.testing.expect(l3.heave_rate_mps_max > l1.heave_rate_mps_max);
}

test "lateral acceleration: 0.1 rad/s^2 at 5 m equals 0.5 m/s^2" {
    const a = try lateralAccelerationFromRollMPS2(0.1, 5.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), a, 1e-12);
}

test "lateral acceleration scales linearly with h" {
    const a1 = try lateralAccelerationFromRollMPS2(0.05, 2.0);
    const a2 = try lateralAccelerationFromRollMPS2(0.05, 4.0);
    try std.testing.expectApproxEqAbs(2.0 * a1, a2, 1e-12);
}

test "inclination at pitch=3, roll=4 is 5" {
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), inclinationDeg(3.0, 4.0), 1e-12);
}

test "inclination at zero is zero" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), inclinationDeg(0.0, 0.0), 1e-12);
}

test "envelope pass: Class 1 with 1.0/1.5/0.5 within limits" {
    try std.testing.expectEqual(Verdict.pass, try envelopeVerdict(.Class_1, 1.0, 1.5, 0.5));
}

test "envelope fail: Class 1 roll 3.0 exceeds 2.5 limit" {
    try std.testing.expectEqual(Verdict.fail, try envelopeVerdict(.Class_1, 1.0, 3.0, 0.5));
}

test "envelope fail: Class 1 heave 1.5 exceeds 0.9 limit" {
    try std.testing.expectEqual(Verdict.fail, try envelopeVerdict(.Class_1, 1.0, 1.5, 1.5));
}

test "envelope fail: combined inclination over 2.0 deg" {
    // pitch=1.5, roll=2.0 -> inclination = sqrt(1.5^2 + 2.0^2) = 2.5
    // exceeds Class 1 inclination limit 2.0.
    try std.testing.expectEqual(Verdict.fail, try envelopeVerdict(.Class_1, 1.5, 2.0, 0.5));
}

test "envelope pass: Class 3 admits more aggressive motions" {
    // pitch=2, roll=3 -> inclination = sqrt(13) ~ 3.6 < 4.0.
    try std.testing.expectEqual(Verdict.pass, try envelopeVerdict(.Class_3, 2.0, 3.0, 1.3));
}

test "input rejection: negative pitch" {
    try std.testing.expectError(Error.NonPositiveAngle, envelopeVerdict(.Class_1, -1.0, 1.0, 0.5));
}

test "input rejection: zero h" {
    try std.testing.expectError(Error.NonPositiveDistance, lateralAccelerationFromRollMPS2(0.1, 0.0));
}
