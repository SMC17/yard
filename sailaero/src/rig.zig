//! Rig-level force aggregation (Hazen/IMS approach as used by the ORC VPP):
//! area-weighted sail coefficients, quadratic viscous drag, induced drag
//! from effective rig height, then drive/side force projection.

const std = @import("std");
const coeffs = @import("coeffs.zig");

pub const rho_air: f64 = 1.225;

pub const Sail = struct {
    coefficients: coeffs.SailCoeffs,
    area_m2: f64,
};

pub const Rig = struct {
    sails: []const Sail,
    /// Effective rig height for induced drag [m] (~ mast height above water
    /// with the ORC effective-span treatment folded into one number).
    effective_height_m: f64,

    pub fn totalArea(self: Rig) f64 {
        var a: f64 = 0;
        for (self.sails) |s| a += s.area_m2;
        return a;
    }
};

pub const Forces = struct {
    /// Force along track, positive forward [N].
    drive_n: f64,
    /// Force athwartships (heeling) [N].
    side_n: f64,
    cl: f64,
    cd: f64,
};

/// Aggregate rig forces at apparent wind angle `beta_deg` and speed `aws`.
pub fn forces(rig: Rig, beta_deg: f64, aws_mps: f64) Forces {
    const area = rig.totalArea();
    if (area <= 0) return .{ .drive_n = 0, .side_n = 0, .cl = 0, .cd = 0 };

    var cl: f64 = 0;
    var cd0: f64 = 0;
    var kp_cl2: f64 = 0;
    for (rig.sails) |s| {
        const w = s.area_m2 / area;
        const c = s.coefficients.at(beta_deg);
        cl += w * c.cl;
        cd0 += w * c.cd0;
        kp_cl2 += w * s.coefficients.kp * c.cl * c.cl;
    }

    // Induced drag from effective aspect ratio AR_e = h_e^2 / A.
    const ar_e = rig.effective_height_m * rig.effective_height_m / area;
    const cdi = cl * cl / (std.math.pi * ar_e);
    const cd = cd0 + kp_cl2 + cdi;

    const q = 0.5 * rho_air * aws_mps * aws_mps * area;
    const beta = std.math.degreesToRadians(beta_deg);
    return .{
        .drive_n = q * (cl * @sin(beta) - cd * @cos(beta)),
        .side_n = q * (cl * @cos(beta) + cd * @sin(beta)),
        .cl = cl,
        .cd = cd,
    };
}

pub fn testSloop() Rig {
    // ~10 m cruiser-racer: 35 m2 main + 25 m2 jib, 14 m effective height.
    return .{
        .sails = &.{
            .{ .coefficients = coeffs.mainsail_high, .area_m2 = 35.0 },
            .{ .coefficients = coeffs.jib_high, .area_m2 = 25.0 },
        },
        .effective_height_m = 14.0,
    };
}

test "no drive head to wind, strong drive on a beam reach" {
    const rig = testSloop();
    const head = forces(rig, 0.0, 8.0);
    try std.testing.expect(head.drive_n < 0); // pure drag pushes backwards
    const beam = forces(rig, 90.0, 8.0);
    try std.testing.expect(beam.drive_n > 0);
    try std.testing.expect(beam.drive_n > forces(rig, 25.0, 8.0).drive_n);
}

test "side force dominates close-hauled" {
    const rig = testSloop();
    const f = forces(rig, 25.0, 8.0);
    try std.testing.expect(f.side_n > 3.0 * @max(f.drive_n, 1.0));
}

test "forces scale with dynamic pressure" {
    const rig = testSloop();
    const f1 = forces(rig, 90.0, 5.0);
    const f2 = forces(rig, 90.0, 10.0);
    try std.testing.expectApproxEqRel(@as(f64, 4.0), f2.drive_n / f1.drive_n, 1e-9);
}

test "induced drag raises total drag above parasitic" {
    const rig = testSloop();
    const f = forces(rig, 28.0, 8.0);
    // At peak lift, induced drag is the dominant drag term for a real rig.
    try std.testing.expect(f.cd > 0.1);
    try std.testing.expect(f.cl > 1.3);
}
