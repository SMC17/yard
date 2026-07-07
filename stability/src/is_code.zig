// IMO 2008 Intact Stability Code Part A 2.2 numerical criteria.
//
// Six numerical thresholds plus a GZ-curve integration step:
//
//   2.2.1.1  area under GZ from 0 to 30 deg     >= 0.055 m * rad
//   2.2.1.2  area under GZ from 0 to 40 deg or
//            to flooding angle                   >= 0.090 m * rad
//   2.2.1.3  area between 30 and 40 deg          >= 0.030 m * rad
//   2.2.1.4  GZ at heel >= 30 deg                >= 0.200 m
//   2.2.1.5  angle of GZ_max                     >= 25 deg
//   2.2.1.6  GM_0                                >= 0.150 m
//
// Source: IMO Resolution MSC.267(85), 2008 IS Code Part A.
// Captured machine-readable at
// ~/codex/sources/standards_machine_readable/imo_is_code_2008_intact_stability.yaml.
//
// This module evaluates the criteria against a GZ curve supplied as
// an array of (angle_rad, GZ_m) sample pairs. Areas are computed by
// trapezoidal integration over the supplied samples; the caller is
// responsible for sample density.

const std = @import("std");

pub const Error = error{
    InsufficientSamples,
    AnglesNotMonotonic,
};

pub const Verdict = enum { pass, fail };

pub const Criteria = struct {
    area_0_30: f64,
    area_0_40: f64,
    area_30_40: f64,
    gz_at_30: f64,
    angle_gz_max_deg: f64,
    gm_0: f64,
};

pub const Result = struct {
    area_0_30: Verdict,
    area_0_40: Verdict,
    area_30_40: Verdict,
    gz_at_30: Verdict,
    angle_gz_max: Verdict,
    gm_0: Verdict,
    overall: Verdict,
    values: Criteria,
};

const deg30: f64 = 30.0 * std.math.pi / 180.0;
const deg40: f64 = 40.0 * std.math.pi / 180.0;
const deg25: f64 = 25.0 * std.math.pi / 180.0;

fn trapezoidArea(angles_rad: []const f64, gz: []const f64, lo: f64, hi: f64) f64 {
    var area: f64 = 0.0;
    var i: usize = 0;
    while (i + 1 < angles_rad.len) : (i += 1) {
        const a0 = angles_rad[i];
        const a1 = angles_rad[i + 1];
        if (a1 <= lo or a0 >= hi) continue;
        const l = if (a0 < lo) lo else a0;
        const h = if (a1 > hi) hi else a1;
        const dx = h - l;
        // Linear interpolation of GZ at l and h.
        const t0 = if (a1 == a0) 0.0 else (l - a0) / (a1 - a0);
        const t1 = if (a1 == a0) 1.0 else (h - a0) / (a1 - a0);
        const gz0 = gz[i] + t0 * (gz[i + 1] - gz[i]);
        const gz1 = gz[i] + t1 * (gz[i + 1] - gz[i]);
        area += 0.5 * (gz0 + gz1) * dx;
    }
    return area;
}

fn interpAt(angles_rad: []const f64, gz: []const f64, target: f64) f64 {
    var i: usize = 0;
    while (i + 1 < angles_rad.len) : (i += 1) {
        if (angles_rad[i] <= target and target <= angles_rad[i + 1]) {
            const t = (target - angles_rad[i]) / (angles_rad[i + 1] - angles_rad[i]);
            return gz[i] + t * (gz[i + 1] - gz[i]);
        }
    }
    return gz[gz.len - 1];
}

fn angleOfMaxGzDeg(angles_rad: []const f64, gz: []const f64) f64 {
    var i_max: usize = 0;
    var max_gz: f64 = gz[0];
    for (gz, 0..) |g, idx| {
        if (g > max_gz) {
            max_gz = g;
            i_max = idx;
        }
    }
    return angles_rad[i_max] * 180.0 / std.math.pi;
}

/// Evaluate all six 2008 IS Code Part A 2.2 numerical criteria against
/// a GZ curve supplied as (angles_rad, GZ_m) samples and a metacentric
/// height GM_0.
pub fn evaluate(angles_rad: []const f64, gz: []const f64, GM_0: f64) Error!Result {
    if (angles_rad.len < 3 or angles_rad.len != gz.len) return Error.InsufficientSamples;
    var i: usize = 0;
    while (i + 1 < angles_rad.len) : (i += 1) {
        if (angles_rad[i + 1] <= angles_rad[i]) return Error.AnglesNotMonotonic;
    }

    const area_0_30 = trapezoidArea(angles_rad, gz, 0.0, deg30);
    const area_0_40 = trapezoidArea(angles_rad, gz, 0.0, deg40);
    const area_30_40 = trapezoidArea(angles_rad, gz, deg30, deg40);
    const gz_at_30 = interpAt(angles_rad, gz, deg30);
    const angle_gz_max = angleOfMaxGzDeg(angles_rad, gz);

    const c: Criteria = .{
        .area_0_30 = area_0_30,
        .area_0_40 = area_0_40,
        .area_30_40 = area_30_40,
        .gz_at_30 = gz_at_30,
        .angle_gz_max_deg = angle_gz_max,
        .gm_0 = GM_0,
    };

    const v_area_0_30: Verdict = if (area_0_30 >= 0.055) .pass else .fail;
    const v_area_0_40: Verdict = if (area_0_40 >= 0.090) .pass else .fail;
    const v_area_30_40: Verdict = if (area_30_40 >= 0.030) .pass else .fail;
    const v_gz_at_30: Verdict = if (gz_at_30 >= 0.200) .pass else .fail;
    const v_angle_gz_max: Verdict = if (angle_gz_max >= 25.0) .pass else .fail;
    const v_gm_0: Verdict = if (GM_0 >= 0.150) .pass else .fail;

    const overall: Verdict = blk: {
        if (v_area_0_30 == .fail or v_area_0_40 == .fail or v_area_30_40 == .fail or
            v_gz_at_30 == .fail or v_angle_gz_max == .fail or v_gm_0 == .fail)
        {
            break :blk .fail;
        }
        break :blk .pass;
    };

    return .{
        .area_0_30 = v_area_0_30,
        .area_0_40 = v_area_0_40,
        .area_30_40 = v_area_30_40,
        .gz_at_30 = v_gz_at_30,
        .angle_gz_max = v_angle_gz_max,
        .gm_0 = v_gm_0,
        .overall = overall,
        .values = c,
    };
}

const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "evaluate rejects insufficient samples" {
    var angles = [_]f64{0.0};
    var gz = [_]f64{0.0};
    try std.testing.expectError(Error.InsufficientSamples, evaluate(&angles, &gz, 0.5));
}

test "evaluate rejects non-monotonic angles" {
    var angles = [_]f64{ 0.0, 0.2, 0.1 };
    var gz = [_]f64{ 0.0, 0.1, 0.05 };
    try std.testing.expectError(Error.AnglesNotMonotonic, evaluate(&angles, &gz, 0.5));
}

test "evaluate passes on synthetic well-behaved hull" {
    // Construct a GZ curve that clears all six thresholds:
    //   GM_0 = 0.3, GZ_max at 40 deg = 0.4, area-rich
    var angles: [16]f64 = undefined;
    var gz: [16]f64 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const deg = @as(f64, @floatFromInt(i)) * 5.0;
        const rad = deg * std.math.pi / 180.0;
        angles[i] = rad;
        // Sinusoidal envelope peaking at 40 deg with GM-consistent slope at zero.
        gz[i] = 0.5 * @sin(rad * 90.0 / 40.0);
    }
    const r = try evaluate(&angles, &gz, 0.3);
    try std.testing.expectEqual(Verdict.pass, r.overall);
}

test "evaluate fails on GM_0 below threshold" {
    var angles: [16]f64 = undefined;
    var gz: [16]f64 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const deg = @as(f64, @floatFromInt(i)) * 5.0;
        const rad = deg * std.math.pi / 180.0;
        angles[i] = rad;
        gz[i] = 0.5 * @sin(rad * 90.0 / 40.0);
    }
    const r = try evaluate(&angles, &gz, 0.10);
    try std.testing.expectEqual(Verdict.fail, r.gm_0);
    try std.testing.expectEqual(Verdict.fail, r.overall);
}

test "evaluate computes 30-degree GZ via interpolation" {
    var angles = [_]f64{ 0.0, deg30, deg40 };
    var gz = [_]f64{ 0.0, 0.25, 0.30 };
    const r = try evaluate(&angles, &gz, 0.3);
    try expectApproxEqAbs(@as(f64, 0.25), r.values.gz_at_30, 1e-12);
}
