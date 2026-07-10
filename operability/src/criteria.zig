//! Seakeeping operability criteria — the naval equivalent of a flight
//! envelope. Sources encoded:
//!
//!   NORDFORSK (1987), "Assessment of Ship Performance in a Seaway" —
//!   the general operability limiting criteria table reproduced in
//!   Faltinsen (1990) Table 3.2 and standard seakeeping texts:
//!
//!     criterion                     merchant   naval    fast small craft
//!     RMS vertical accel (fwd perp)  0.275 g   0.275 g  0.65 g
//!     RMS vertical accel (bridge)    0.15 g    0.20 g   0.275 g
//!     RMS lateral accel (bridge)     0.12 g    0.10 g   0.10 g
//!     RMS roll                       6.0 deg   4.0 deg  4.0 deg
//!     slamming probability           0.03/0.06 0.03     0.03
//!     deck wetness probability       0.05      0.05     0.05
//!
//!   (slamming: 0.03 for L>=100 m, 0.06 for L<=100 m merchant hulls)
//!
//! STANAG 4154 (NATO) uses the same criterion structure with mission-
//! specific limits; the naval column here is the common general-operations
//! set. Values are RMS (standard deviation), not significant amplitudes.

const std = @import("std");

pub const g: f64 = 9.80665;

pub const ShipClass = enum { merchant, naval, fast_small_craft };

pub const Limits = struct {
    rms_vert_accel_fp_g: f64,
    rms_vert_accel_bridge_g: f64,
    rms_lat_accel_bridge_g: f64,
    rms_roll_deg: f64,
    slam_probability: f64,
    wetness_probability: f64,
};

pub fn limits(class: ShipClass, length_m: f64) Limits {
    return switch (class) {
        .merchant => .{
            .rms_vert_accel_fp_g = 0.275,
            .rms_vert_accel_bridge_g = 0.15,
            .rms_lat_accel_bridge_g = 0.12,
            .rms_roll_deg = 6.0,
            .slam_probability = if (length_m >= 100.0) 0.03 else 0.06,
            .wetness_probability = 0.05,
        },
        .naval => .{
            .rms_vert_accel_fp_g = 0.275,
            .rms_vert_accel_bridge_g = 0.20,
            .rms_lat_accel_bridge_g = 0.10,
            .rms_roll_deg = 4.0,
            .slam_probability = 0.03,
            .wetness_probability = 0.05,
        },
        .fast_small_craft => .{
            .rms_vert_accel_fp_g = 0.65,
            .rms_vert_accel_bridge_g = 0.275,
            .rms_lat_accel_bridge_g = 0.10,
            .rms_roll_deg = 4.0,
            .slam_probability = 0.03,
            .wetness_probability = 0.05,
        },
    };
}

pub const Responses = struct {
    /// RMS values from the spectral chain (sqrt of zeroth moments).
    rms_vert_accel_fp_ms2: f64,
    rms_vert_accel_bridge_ms2: f64,
    rms_lat_accel_bridge_ms2: f64,
    rms_roll_deg: f64,
    slam_probability: f64,
    wetness_probability: f64,
};

pub const CriterionResult = struct {
    pass: bool,
    value: f64,
    limit: f64,
};

pub const Assessment = struct {
    vert_accel_fp: CriterionResult,
    vert_accel_bridge: CriterionResult,
    lat_accel_bridge: CriterionResult,
    roll: CriterionResult,
    slamming: CriterionResult,
    wetness: CriterionResult,
    operable: bool,
};

pub fn assess(class: ShipClass, length_m: f64, r: Responses) Assessment {
    const lim = limits(class, length_m);
    const checks = [_]CriterionResult{
        .{ .value = r.rms_vert_accel_fp_ms2 / g, .limit = lim.rms_vert_accel_fp_g, .pass = r.rms_vert_accel_fp_ms2 / g <= lim.rms_vert_accel_fp_g },
        .{ .value = r.rms_vert_accel_bridge_ms2 / g, .limit = lim.rms_vert_accel_bridge_g, .pass = r.rms_vert_accel_bridge_ms2 / g <= lim.rms_vert_accel_bridge_g },
        .{ .value = r.rms_lat_accel_bridge_ms2 / g, .limit = lim.rms_lat_accel_bridge_g, .pass = r.rms_lat_accel_bridge_ms2 / g <= lim.rms_lat_accel_bridge_g },
        .{ .value = r.rms_roll_deg, .limit = lim.rms_roll_deg, .pass = r.rms_roll_deg <= lim.rms_roll_deg },
        .{ .value = r.slam_probability, .limit = lim.slam_probability, .pass = r.slam_probability <= lim.slam_probability },
        .{ .value = r.wetness_probability, .limit = lim.wetness_probability, .pass = r.wetness_probability <= lim.wetness_probability },
    };
    var all = true;
    for (checks) |c| all = all and c.pass;
    return .{
        .vert_accel_fp = checks[0],
        .vert_accel_bridge = checks[1],
        .lat_accel_bridge = checks[2],
        .roll = checks[3],
        .slamming = checks[4],
        .wetness = checks[5],
        .operable = all,
    };
}

test "naval limits are stricter than merchant where they differ" {
    const m = limits(.merchant, 120.0);
    const n = limits(.naval, 120.0);
    try std.testing.expect(n.rms_roll_deg < m.rms_roll_deg);
    try std.testing.expect(n.rms_lat_accel_bridge_g < m.rms_lat_accel_bridge_g);
    // Bridge vertical acceleration: naval crews tolerate more than
    // merchant habitability demands.
    try std.testing.expect(n.rms_vert_accel_bridge_g > m.rms_vert_accel_bridge_g);
}

test "short merchant hulls get the relaxed slam criterion" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.06), limits(.merchant, 80.0).slam_probability, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.03), limits(.merchant, 150.0).slam_probability, 1e-12);
}

test "assessment gates on every criterion" {
    const calm = Responses{
        .rms_vert_accel_fp_ms2 = 0.5,
        .rms_vert_accel_bridge_ms2 = 0.3,
        .rms_lat_accel_bridge_ms2 = 0.2,
        .rms_roll_deg = 2.0,
        .slam_probability = 0.005,
        .wetness_probability = 0.01,
    };
    try std.testing.expect(assess(.naval, 120.0, calm).operable);

    var rolling = calm;
    rolling.rms_roll_deg = 5.0; // fails naval (4.0), passes merchant (6.0)
    try std.testing.expect(!assess(.naval, 120.0, rolling).operable);
    try std.testing.expect(assess(.merchant, 120.0, rolling).operable);
}
