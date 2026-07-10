//! Steady-state speed polar: balance sail drive against hull resistance.
//!
//! The hull is abstract — callers supply a resistance table R(v) (from the
//! resistance/savitsky modules, tank data, or an era hull model) plus the
//! draft of the lateral plane. Two hydrodynamic sinks oppose the sail drive:
//!   - table resistance R(v) (calm-water drag), and
//!   - leeway-induced drag from reacting the rig's side force: lifting-line
//!     with the free-surface mirror (effective span 2T),
//!       R_lee = F_side^2 / (0.5 rho_w v^2 pi (2T)^2 e).
//! The apparent-wind feedback is solved implicitly: the boat's own speed
//! shifts the apparent wind forward and changes the available drive.
//! Deterministic scan + bisection.

const std = @import("std");
const apparent = @import("apparent.zig");
const rig_mod = @import("rig.zig");
const squarerig = @import("squarerig.zig");

pub const rho_water: f64 = 1025.0;

pub const RigKind = union(enum) {
    fore_and_aft: rig_mod.Rig,
    square: squarerig.SquareRig,
};

pub const Hull = struct {
    /// Draft of the lateral plane (keel included) [m].
    draft_m: f64,
    /// Oswald-style span efficiency of keel + hull as a side-force surface.
    span_efficiency: f64 = 0.7,
};

pub const ResistancePoint = struct {
    v_mps: f64,
    r_n: f64,
};

pub fn resistanceAt(table: []const ResistancePoint, v: f64) f64 {
    std.debug.assert(table.len >= 2);
    const clamped = @min(@max(v, table[0].v_mps), table[table.len - 1].v_mps);
    var i: usize = 1;
    while (i < table.len and table[i].v_mps < clamped) i += 1;
    if (i == table.len) i -= 1;
    const p0 = table[i - 1];
    const p1 = table[i];
    const t = if (p1.v_mps == p0.v_mps) 0.0 else (clamped - p0.v_mps) / (p1.v_mps - p0.v_mps);
    return p0.r_n + t * (p1.r_n - p0.r_n);
}

pub const RigForces = struct {
    drive_n: f64,
    side_n: f64,
};

pub fn rigForces(kind: RigKind, beta_deg: f64, aws_mps: f64) RigForces {
    return switch (kind) {
        .fore_and_aft => |r| blk: {
            const f = rig_mod.forces(r, beta_deg, aws_mps);
            break :blk .{ .drive_n = f.drive_n, .side_n = f.side_n };
        },
        .square => |sq| blk: {
            const f = squarerig.forces(sq, beta_deg, aws_mps);
            break :blk .{ .drive_n = f.drive_n, .side_n = f.side_n };
        },
    };
}

fn netForce(kind: RigKind, hull: Hull, tws: f64, twa: f64, table: []const ResistancePoint, v: f64) f64 {
    const aw = apparent.compute(tws, twa, v);
    const f = rigForces(kind, aw.angle_deg, aw.speed_mps);
    const span = 2.0 * hull.draft_m;
    const r_lee = f.side_n * f.side_n /
        (0.5 * rho_water * v * v * std.math.pi * span * span * hull.span_efficiency);
    return f.drive_n - resistanceAt(table, v) - r_lee;
}

/// Steady boat speed at true wind speed/angle, 0 if the rig cannot drive
/// the hull at this angle.
pub fn speedAt(kind: RigKind, hull: Hull, tws_mps: f64, twa_deg: f64, table: []const ResistancePoint) f64 {
    const v_max = table[table.len - 1].v_mps;
    if (netForce(kind, hull, tws_mps, twa_deg, table, v_max) > 0) return v_max;

    // Leeway drag diverges as v -> 0, so scan downward for the fastest
    // speed with positive net force, then bisect up to the sign change.
    const n_scan: usize = 240;
    var i: usize = n_scan;
    while (i > 0) : (i -= 1) {
        const v = v_max * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n_scan + 1));
        if (netForce(kind, hull, tws_mps, twa_deg, table, v) > 0) {
            var lo = v;
            var hi = v_max * @as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(n_scan + 1));
            var it: usize = 0;
            while (it < 50) : (it += 1) {
                const mid = 0.5 * (lo + hi);
                if (netForce(kind, hull, tws_mps, twa_deg, table, mid) > 0) {
                    lo = mid;
                } else {
                    hi = mid;
                }
            }
            return 0.5 * (lo + hi);
        }
    }
    return 0.0;
}

/// Upwind velocity-made-good over a TWA sweep. Returns best VMG and angle.
pub fn bestUpwindVmg(kind: RigKind, hull: Hull, tws_mps: f64, table: []const ResistancePoint) struct { vmg_mps: f64, twa_deg: f64 } {
    var best_vmg: f64 = 0;
    var best_twa: f64 = 0;
    var twa: f64 = 20.0;
    while (twa <= 90.0) : (twa += 1.0) {
        const v = speedAt(kind, hull, tws_mps, twa, table);
        const vmg = v * @cos(std.math.degreesToRadians(twa));
        if (vmg > best_vmg) {
            best_vmg = vmg;
            best_twa = twa;
        }
    }
    return .{ .vmg_mps = best_vmg, .twa_deg = best_twa };
}

fn quadraticTable(comptime n: usize, c: f64, v_max: f64) [n]ResistancePoint {
    var t: [n]ResistancePoint = undefined;
    for (&t, 0..) |*p, i| {
        const v = v_max * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n - 1));
        p.* = .{ .v_mps = v, .r_n = c * v * v };
    }
    return t;
}

// ~10 m sloop: R = 150 v^2 (2.4 kN at 4 m/s), keel draft 1.8 m.
const sloop_table = quadraticTable(31, 150.0, 15.0);
const sloop_hull = Hull{ .draft_m = 1.8 };
// Tea clipper: R = 5000 v^2 (320 kN at 8 m/s ~ 3.4 MW effective), draft 6 m.
const clipper_table = quadraticTable(31, 5000.0, 15.0);
const clipper_hull = Hull{ .draft_m = 6.0 };

test "sloop: dead zone upwind, sails on a reach" {
    const kind: RigKind = .{ .fore_and_aft = rig_mod.testSloop() };
    try std.testing.expectEqual(@as(f64, 0.0), speedAt(kind, sloop_hull, 8.0, 0.0, &sloop_table));
    try std.testing.expectEqual(@as(f64, 0.0), speedAt(kind, sloop_hull, 8.0, 15.0, &sloop_table));
    try std.testing.expectEqual(@as(f64, 0.0), speedAt(kind, sloop_hull, 8.0, 24.0, &sloop_table));
    const reach = speedAt(kind, sloop_hull, 8.0, 90.0, &sloop_table);
    try std.testing.expect(reach > 2.0 and reach < 10.0);
}

test "sloop: speed monotonic in wind speed at fixed angle" {
    const kind: RigKind = .{ .fore_and_aft = rig_mod.testSloop() };
    const v1 = speedAt(kind, sloop_hull, 5.0, 90.0, &sloop_table);
    const v2 = speedAt(kind, sloop_hull, 8.0, 90.0, &sloop_table);
    const v3 = speedAt(kind, sloop_hull, 12.0, 90.0, &sloop_table);
    try std.testing.expect(v2 > v1);
    try std.testing.expect(v3 > v2);
}

test "sloop: meaningful upwind VMG at a close-hauled angle" {
    const kind: RigKind = .{ .fore_and_aft = rig_mod.testSloop() };
    const best = bestUpwindVmg(kind, sloop_hull, 8.0, &sloop_table);
    try std.testing.expect(best.vmg_mps > 0.5);
    try std.testing.expect(best.twa_deg > 30.0 and best.twa_deg < 70.0);
}

test "clipper: cannot beat, sails free" {
    const kind: RigKind = .{ .square = squarerig.testClipper() };
    // Six points off the true wind (~67 deg) was the practical limit for a
    // square-rigger; leeway drag + brace limit reproduce a wide dead zone.
    try std.testing.expectEqual(@as(f64, 0.0), speedAt(kind, clipper_hull, 10.0, 45.0, &clipper_table));
    try std.testing.expectEqual(@as(f64, 0.0), speedAt(kind, clipper_hull, 10.0, 55.0, &clipper_table));
    const beam = speedAt(kind, clipper_hull, 10.0, 90.0, &clipper_table);
    const broad = speedAt(kind, clipper_hull, 10.0, 135.0, &clipper_table);
    try std.testing.expect(beam > 3.0);
    try std.testing.expect(broad > 3.0);
}

test "clipper points lower than the sloop" {
    const sloop_kind: RigKind = .{ .fore_and_aft = rig_mod.testSloop() };
    const clipper_kind: RigKind = .{ .square = squarerig.testClipper() };
    const sloop_best = bestUpwindVmg(sloop_kind, sloop_hull, 8.0, &sloop_table);
    const clipper_best = bestUpwindVmg(clipper_kind, clipper_hull, 8.0, &clipper_table);
    // The square rig's best upwind angle is markedly wider (or it has none).
    try std.testing.expect(clipper_best.vmg_mps == 0.0 or clipper_best.twa_deg > sloop_best.twa_deg + 10.0);
}
