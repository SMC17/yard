//! Square-rig force model for Age-of-Sail missions.
//!
//! Engineering approximation, documented rather than hidden: the sail plan
//! acts as a low-aspect-ratio plate on braced yards. With angle of attack
//! alpha between apparent wind and the sail plane:
//!   CL = cl_peak * sin(2*alpha)      (thin/flat plate lift, peak at 45 deg)
//!   CD = cd0 + cd90 * sin^2(alpha)   (normal-plate drag asymptote at 90 deg)
//! cd90 ~ 1.9 is the classic normal flat-plate value; cl_peak ~ 0.9 reflects
//! low-aspect square sails; cd0 ~ 0.4 carries the standing rigging, spars,
//! and top-hamper windage of a full rig — which is what actually kills
//! pointing ability (it only opposes drive when cos(beta) > 0). The yards
//! cannot brace closer than `min_brace_deg` to the centreline. Drive is
//! maximised over the allowed brace range at each apparent angle.
//! Validation rung: clipper passage data (qualitative polars only in v0).

const std = @import("std");
const rig_mod = @import("rig.zig");

pub const SquareRig = struct {
    total_area_m2: f64,
    /// Closest the yards brace to the centreline [deg]. ~30 for a full-rigger.
    min_brace_deg: f64 = 30.0,
    cl_peak: f64 = 0.9,
    /// Parasitic drag incl. standing rigging / spar windage.
    cd0: f64 = 0.40,
    cd90: f64 = 1.9,
};

pub const Forces = struct {
    drive_n: f64,
    side_n: f64,
    /// Brace angle from centreline that maximised drive [deg].
    brace_deg: f64,
};

fn forcesAtBrace(sq: SquareRig, beta_deg: f64, aws_mps: f64, brace_deg: f64) struct { drive: f64, side: f64 } {
    // Angle of attack between apparent wind and sail plane; the plate is
    // symmetric, so attack beyond 90 deg reflects.
    var alpha_deg = beta_deg - brace_deg;
    if (alpha_deg > 90.0) alpha_deg = 180.0 - alpha_deg;
    const alpha = std.math.degreesToRadians(@min(@max(alpha_deg, 0.0), 90.0));
    const cl = sq.cl_peak * @sin(2.0 * alpha);
    const cd = sq.cd0 + sq.cd90 * @sin(alpha) * @sin(alpha);

    // Lift is normal to the apparent wind, drag along it; project on track.
    const beta = std.math.degreesToRadians(beta_deg);
    const q = 0.5 * rig_mod.rho_air * aws_mps * aws_mps * sq.total_area_m2;
    return .{
        .drive = q * (cl * @sin(beta) - cd * @cos(beta)),
        .side = q * (cl * @cos(beta) + cd * @sin(beta)),
    };
}

/// Best-drive forces at apparent wind angle `beta_deg`, searching the brace
/// range in 1-degree steps (deterministic).
pub fn forces(sq: SquareRig, beta_deg: f64, aws_mps: f64) Forces {
    var best_drive = -std.math.inf(f64);
    var best_side: f64 = 0;
    var best_brace: f64 = sq.min_brace_deg;
    var brace = sq.min_brace_deg;
    while (brace <= 90.0) : (brace += 1.0) {
        const f = forcesAtBrace(sq, beta_deg, aws_mps, brace);
        if (f.drive > best_drive) {
            best_drive = f.drive;
            best_side = f.side;
            best_brace = brace;
        }
    }
    return .{ .drive_n = best_drive, .side_n = best_side, .brace_deg = best_brace };
}

pub fn testClipper() SquareRig {
    // Tea-clipper order of magnitude: ~3000 m2 of canvas.
    return .{ .total_area_m2 = 3000.0 };
}

test "square rig cannot make way close to the wind" {
    const sq = testClipper();
    // Inside ~40 deg apparent the brace limit caps angle of attack so low
    // that rig windage beats the lift projection.
    try std.testing.expect(forces(sq, 40.0, 8.0).drive_n < 0);
    try std.testing.expect(forces(sq, 35.0, 8.0).drive_n < 0);
    try std.testing.expect(forces(sq, 20.0, 8.0).drive_n < 0);
}

test "square rig drives hard off the wind" {
    const sq = testClipper();
    const beam = forces(sq, 90.0, 8.0);
    const broad = forces(sq, 135.0, 8.0);
    try std.testing.expect(beam.drive_n > 0);
    try std.testing.expect(broad.drive_n > 0);
    // Off the wind it out-drives its own close-reach performance.
    try std.testing.expect(broad.drive_n > forces(sq, 70.0, 8.0).drive_n);
}

test "dead run: pure drag propulsion, yards square" {
    const sq = testClipper();
    const run = forces(sq, 180.0, 8.0);
    try std.testing.expect(run.drive_n > 0);
    // At beta=180 the drag plate is fully square to the wind.
    try std.testing.expectApproxEqAbs(@as(f64, 90.0), run.brace_deg, 1.5);
    // Drive equals the full drag force: q * (cd0 + cd90).
    const q = 0.5 * rig_mod.rho_air * 64.0 * sq.total_area_m2;
    try std.testing.expectApproxEqRel(q * (sq.cd0 + sq.cd90), run.drive_n, 1e-9);
}

test "fore-and-aft rig points higher than square rig" {
    const sloop = rig_mod.testSloop();
    const sq = testClipper();
    // At 35 deg apparent, the sloop drives; the square rig does not.
    const sloop_f = rig_mod.forces(sloop, 35.0, 8.0);
    const sq_f = forces(sq, 35.0, 8.0);
    try std.testing.expect(sloop_f.drive_n > 0);
    try std.testing.expect(sq_f.drive_n < 0);
}
