//! IMO MSC.137(76) manoeuvrability criteria, exact.

const std = @import("std");

/// 10/10 zig-zag first-overshoot limit [deg] as a function of L/V [s].
pub fn zigzag1010FirstOvershootLimit(l_over_v_s: f64) f64 {
    if (l_over_v_s < 10.0) return 10.0;
    if (l_over_v_s < 30.0) return 5.0 + 0.5 * l_over_v_s;
    return 20.0;
}

/// 10/10 zig-zag second-overshoot limit [deg].
pub fn zigzag1010SecondOvershootLimit(l_over_v_s: f64) f64 {
    if (l_over_v_s < 10.0) return 25.0;
    if (l_over_v_s < 30.0) return 17.5 + 0.75 * l_over_v_s;
    return 40.0;
}

/// 20/20 zig-zag first-overshoot limit [deg].
pub const zigzag2020_first_overshoot_limit_deg: f64 = 25.0;

pub const Trial = struct {
    length_m: f64,
    speed_mps: f64,
    /// 35-deg rudder turning circle.
    advance_m: f64,
    tactical_diameter_m: f64,
    /// Distance travelled when heading has changed 10 deg with 10 deg rudder.
    initial_turning_distance_m: f64,
    zigzag_1010_first_overshoot_deg: f64,
    zigzag_1010_second_overshoot_deg: f64,
    zigzag_2020_first_overshoot_deg: f64,
    /// Full-astern stopping track reach.
    track_reach_m: f64,
};

pub const Check = struct { pass: bool, value: f64, limit: f64 };

pub const Assessment = struct {
    turning_advance: Check,
    tactical_diameter: Check,
    initial_turning: Check,
    zigzag_1010_first: Check,
    zigzag_1010_second: Check,
    zigzag_2020_first: Check,
    stopping: Check,
    compliant: bool,
};

pub fn assess(t: Trial) Assessment {
    const l = t.length_m;
    const lv = l / t.speed_mps;
    const checks = [_]Check{
        .{ .value = t.advance_m, .limit = 4.5 * l, .pass = t.advance_m <= 4.5 * l },
        .{ .value = t.tactical_diameter_m, .limit = 5.0 * l, .pass = t.tactical_diameter_m <= 5.0 * l },
        .{ .value = t.initial_turning_distance_m, .limit = 2.5 * l, .pass = t.initial_turning_distance_m <= 2.5 * l },
        .{ .value = t.zigzag_1010_first_overshoot_deg, .limit = zigzag1010FirstOvershootLimit(lv), .pass = t.zigzag_1010_first_overshoot_deg <= zigzag1010FirstOvershootLimit(lv) },
        .{ .value = t.zigzag_1010_second_overshoot_deg, .limit = zigzag1010SecondOvershootLimit(lv), .pass = t.zigzag_1010_second_overshoot_deg <= zigzag1010SecondOvershootLimit(lv) },
        .{ .value = t.zigzag_2020_first_overshoot_deg, .limit = zigzag2020_first_overshoot_limit_deg, .pass = t.zigzag_2020_first_overshoot_deg <= zigzag2020_first_overshoot_limit_deg },
        .{ .value = t.track_reach_m, .limit = 15.0 * l, .pass = t.track_reach_m <= 15.0 * l },
    };
    var all = true;
    for (checks) |c| all = all and c.pass;
    return .{
        .turning_advance = checks[0],
        .tactical_diameter = checks[1],
        .initial_turning = checks[2],
        .zigzag_1010_first = checks[3],
        .zigzag_1010_second = checks[4],
        .zigzag_2020_first = checks[5],
        .stopping = checks[6],
        .compliant = all,
    };
}

test "overshoot limits match the resolution at the breakpoints" {
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), zigzag1010FirstOvershootLimit(9.99), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), zigzag1010FirstOvershootLimit(10.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), zigzag1010FirstOvershootLimit(20.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), zigzag1010FirstOvershootLimit(30.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), zigzag1010FirstOvershootLimit(50.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 25.0), zigzag1010SecondOvershootLimit(5.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 32.5), zigzag1010SecondOvershootLimit(20.0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 40.0), zigzag1010SecondOvershootLimit(30.0), 1e-12);
}

test "a well-behaved trial passes; a sluggish one fails the right criteria" {
    // 150 m ship at 7.7 m/s: L/V = 19.5 s -> first overshoot limit 14.7 deg.
    const good = Trial{
        .length_m = 150,
        .speed_mps = 7.7,
        .advance_m = 480,
        .tactical_diameter_m = 600,
        .initial_turning_distance_m = 300,
        .zigzag_1010_first_overshoot_deg = 8.0,
        .zigzag_1010_second_overshoot_deg = 15.0,
        .zigzag_2020_first_overshoot_deg = 14.0,
        .track_reach_m = 1500,
    };
    try std.testing.expect(assess(good).compliant);

    var bad = good;
    bad.zigzag_1010_first_overshoot_deg = 16.0; // > 14.74 limit
    bad.tactical_diameter_m = 800; // > 750
    const a = assess(bad);
    try std.testing.expect(!a.compliant);
    try std.testing.expect(!a.zigzag_1010_first.pass);
    try std.testing.expect(!a.tactical_diameter.pass);
    try std.testing.expect(a.stopping.pass);
}
