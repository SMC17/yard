//! Sail force coefficients, ORC VPP Documentation 2023.
//!
//! Tables transcribed from ORC VPP 2023: Table 5.1 (mainsail) and Table 5.4
//! (jib/genoa). CD0 is parasitic drag; kp is the two-dimensional quadratic
//! viscous drag coefficient (CD_visc = kp * CL^2); induced drag is added at
//! rig level from effective aspect ratio. "low"/"high" sets follow the ORC
//! rigging-arrangement distinction (checkstay / adjustable-forestay ability
//! to add camber in light airs).

const std = @import("std");

pub const Point = struct {
    beta_deg: f64,
    cd0: f64,
    cl: f64,
};

pub const SailCoeffs = struct {
    points: []const Point,
    /// Quadratic viscous drag coefficient.
    kp: f64,

    pub fn at(self: SailCoeffs, beta_deg: f64) struct { cd0: f64, cl: f64 } {
        const pts = self.points;
        const b = @min(@max(beta_deg, pts[0].beta_deg), pts[pts.len - 1].beta_deg);
        var i: usize = 1;
        while (i < pts.len and pts[i].beta_deg < b) i += 1;
        if (i == pts.len) i -= 1;
        const p0 = pts[i - 1];
        const p1 = pts[i];
        const t = if (p1.beta_deg == p0.beta_deg) 0.0 else (b - p0.beta_deg) / (p1.beta_deg - p0.beta_deg);
        return .{
            .cd0 = p0.cd0 + t * (p1.cd0 - p0.cd0),
            .cl = p0.cl + t * (p1.cl - p0.cl),
        };
    }
};

/// ORC VPP 2023 Table 5.1, mainsail, low set (no checkstays). kpm = 0.01379.
pub const mainsail_low = SailCoeffs{
    .kp = 0.01379,
    .points = &.{
        .{ .beta_deg = 0, .cd0 = 0.04310, .cl = 0.00000 },
        .{ .beta_deg = 7, .cd0 = 0.02586, .cl = 0.86207 },
        .{ .beta_deg = 9, .cd0 = 0.02328, .cl = 1.05172 },
        .{ .beta_deg = 12, .cd0 = 0.02328, .cl = 1.16379 },
        .{ .beta_deg = 28, .cd0 = 0.03259, .cl = 1.34698 },
        .{ .beta_deg = 60, .cd0 = 0.11302, .cl = 1.35345 },
        .{ .beta_deg = 90, .cd0 = 0.38250, .cl = 1.26724 },
        .{ .beta_deg = 120, .cd0 = 0.96888, .cl = 0.93103 },
        .{ .beta_deg = 150, .cd0 = 1.31578, .cl = 0.38793 },
        .{ .beta_deg = 180, .cd0 = 1.34483, .cl = -0.11207 },
    },
};

/// ORC VPP 2023 Table 5.1, mainsail, high set (checkstays fitted).
pub const mainsail_high = SailCoeffs{
    .kp = 0.01379,
    .points = &.{
        .{ .beta_deg = 0, .cd0 = 0.03448, .cl = 0.00000 },
        .{ .beta_deg = 7, .cd0 = 0.01724, .cl = 0.94828 },
        .{ .beta_deg = 9, .cd0 = 0.01466, .cl = 1.13793 },
        .{ .beta_deg = 12, .cd0 = 0.01466, .cl = 1.25000 },
        .{ .beta_deg = 28, .cd0 = 0.02586, .cl = 1.42681 },
        .{ .beta_deg = 60, .cd0 = 0.11302, .cl = 1.38319 },
        .{ .beta_deg = 90, .cd0 = 0.38250, .cl = 1.26724 },
        .{ .beta_deg = 120, .cd0 = 0.96888, .cl = 0.93103 },
        .{ .beta_deg = 150, .cd0 = 1.31578, .cl = 0.38793 },
        .{ .beta_deg = 180, .cd0 = 1.34483, .cl = -0.11207 },
    },
};

/// ORC VPP 2023 Table 5.4, jib/genoa, low set (no adjustable forestay). kpj = 0.016.
pub const jib_low = SailCoeffs{
    .kp = 0.016,
    .points = &.{
        .{ .beta_deg = 7, .cd0 = 0.05000, .cl = 0.00000 },
        .{ .beta_deg = 15, .cd0 = 0.03200, .cl = 1.00000 },
        .{ .beta_deg = 20, .cd0 = 0.03100, .cl = 1.37500 },
        .{ .beta_deg = 27, .cd0 = 0.03700, .cl = 1.45000 },
        .{ .beta_deg = 50, .cd0 = 0.25000, .cl = 1.45000 },
        .{ .beta_deg = 60, .cd0 = 0.35000, .cl = 1.25000 },
        .{ .beta_deg = 100, .cd0 = 0.73000, .cl = 0.40000 },
        .{ .beta_deg = 150, .cd0 = 0.95000, .cl = 0.00000 },
        .{ .beta_deg = 180, .cd0 = 0.90000, .cl = -0.10000 },
    },
};

/// ORC VPP 2023 Table 5.4, jib/genoa, high set (adjustable forestay).
pub const jib_high = SailCoeffs{
    .kp = 0.016,
    .points = &.{
        .{ .beta_deg = 7, .cd0 = 0.05000, .cl = 0.00000 },
        .{ .beta_deg = 15, .cd0 = 0.03200, .cl = 1.10000 },
        .{ .beta_deg = 20, .cd0 = 0.03100, .cl = 1.47500 },
        .{ .beta_deg = 27, .cd0 = 0.03700, .cl = 1.50000 },
        .{ .beta_deg = 50, .cd0 = 0.25000, .cl = 1.45000 },
        .{ .beta_deg = 60, .cd0 = 0.35000, .cl = 1.25000 },
        .{ .beta_deg = 100, .cd0 = 0.73000, .cl = 0.40000 },
        .{ .beta_deg = 150, .cd0 = 0.95000, .cl = 0.00000 },
        .{ .beta_deg = 180, .cd0 = 0.90000, .cl = -0.10000 },
    },
};

test "interpolation reproduces table nodes exactly" {
    const m = mainsail_low.at(28.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.03259), m.cd0, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.34698), m.cl, 1e-12);
    const j = jib_high.at(20.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.47500), j.cl, 1e-12);
}

test "interpolation between nodes is linear" {
    // Mainsail low, midway between 12 and 28 deg.
    const m = mainsail_low.at(20.0);
    try std.testing.expectApproxEqAbs((1.16379 + 1.34698) / 2.0, m.cl, 1e-12);
}

test "coefficient physics: lift peaks reaching, dies downwind" {
    try std.testing.expect(mainsail_low.at(60.0).cl > 1.3);
    try std.testing.expect(mainsail_low.at(180.0).cl < 0.0);
    try std.testing.expect(mainsail_low.at(180.0).cd0 > 1.3);
    // Jib fills later than the main (zero lift at 7 deg).
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), jib_low.at(7.0).cl, 1e-12);
}

test "out-of-range angles clamp" {
    const m = mainsail_low.at(200.0);
    try std.testing.expectApproxEqAbs(@as(f64, -0.11207), m.cl, 1e-12);
}
