//! Sail-passage physics: hull resistance table and course-made-good speed.

const std = @import("std");
const resistance = @import("yard_resistance");
const sailaero = @import("yard_sailaero");
const spec = @import("spec.zig");

pub const rho_water: f64 = 1025.0;
pub const nu_water: f64 = 1.19e-6;
pub const table_len: usize = 25;
pub const v_max_mps: f64 = 12.0;

/// R(v) = 0.5 rho S v^2 (k C_f(Re) + C_r) — ITTC-57 friction line with a
/// form factor plus a documented residuary coefficient. Holtrop is not used
/// here: sailing-era hulls sit outside its regression envelope (B/T < 2.1).
pub fn resistanceTable(hull: spec.Hull) [table_len]sailaero.polar.ResistancePoint {
    var t: [table_len]sailaero.polar.ResistancePoint = undefined;
    for (&t, 0..) |*p, i| {
        const v = v_max_mps * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(table_len - 1));
        var r: f64 = 0;
        if (v > 0) {
            const re = resistance.ittc57.reynolds(v, hull.loa_m, nu_water);
            const cf = resistance.ittc57.cF(re) catch 0.002;
            r = 0.5 * rho_water * hull.wetted_surface_m2 * v * v *
                (hull.form_factor * cf + hull.cr);
        }
        p.* = .{ .v_mps = v, .r_n = r };
    }
    return t;
}

pub fn rigKind(rig: spec.Rig) sailaero.polar.RigKind {
    return switch (rig.kind) {
        .square => .{ .square = .{
            .total_area_m2 = rig.area_m2,
            .min_brace_deg = rig.min_brace_deg,
        } },
        .fore_and_aft => .{ .fore_and_aft = .{
            .sails = &.{.{
                .coefficients = sailaero.coeffs.mainsail_low,
                .area_m2 = rig.area_m2,
            }},
            .effective_height_m = rig.effective_height_m,
        } },
    };
}

/// Course-made-good speed with routing freedom: the ship may head off the
/// direct course by theta (bearing away to fill the sails, or tacking
/// toward the wind); progress is v(polar at the resulting wind angle) x
/// cos(theta). Deterministic 2-degree sweep, both tacks covered by the
/// sign of theta. This is what a competent watch actually does — without
/// it a drawn header parks the ship, which no clipper master allowed.
pub fn madeGoodSpeed(
    kind: sailaero.polar.RigKind,
    hull_plane: sailaero.polar.Hull,
    tws_mps: f64,
    twa_deg: f64,
    table: []const sailaero.polar.ResistancePoint,
) f64 {
    var best: f64 = 0;
    var theta: f64 = -88.0;
    while (theta <= 88.0) : (theta += 2.0) {
        const wind_angle = @min(@abs(twa_deg - theta), 180.0);
        const v = sailaero.polar.speedAt(kind, hull_plane, tws_mps, wind_angle, table);
        const progress = v * @cos(std.math.degreesToRadians(theta));
        if (progress > best) best = progress;
    }
    return best;
}

const fixtures = @import("fixtures.zig");

fn cuttyHull() spec.Hull {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Inline the reference values (kept in fixtures.zig JSON for the CLI).
    return .{
        .loa_m = 64.7,
        .beam_m = 11.0,
        .draft_m = 6.1,
        .depth_m = 7.5,
        .cb = 0.55,
        .displacement_m3 = 2080,
        .wetted_surface_m2 = 1010,
        .kg_m = 3.7,
        .cr = 0.0012,
    };
}

test "clipper resistance is the right order of magnitude" {
    const t = resistanceTable(cuttyHull());
    // At ~8 kt (4.1 m/s): tens of kN, far below the sail drive available.
    const r4 = sailaero.polar.resistanceAt(&t, 4.0);
    try std.testing.expect(r4 > 10_000 and r4 < 60_000);
    // Effective power at 15 kt within a plausible clipper band (< 3 MW).
    const r77 = sailaero.polar.resistanceAt(&t, 7.7);
    try std.testing.expect(r77 * 7.7 < 3.0e6);
}

test "made-good speed: bearing away rescues a header" {
    const hull = cuttyHull();
    const t = resistanceTable(hull);
    const kind = rigKind(.{ .kind = .square, .area_m2 = 2970, .min_brace_deg = 30 });
    const plane = sailaero.polar.Hull{ .draft_m = hull.draft_m };

    // Direct course dead upwind: still makes some way by tacking.
    const beat = madeGoodSpeed(kind, plane, 8.0, 0.0, &t);
    try std.testing.expect(beat > 0.3 and beat < 1.6); // ~0.6-3 kt VMG

    // Wind 60 deg off course: bearing away beats sailing the header.
    const direct = sailaero.polar.speedAt(kind, plane, 8.0, 60.0, &t);
    const made_good = madeGoodSpeed(kind, plane, 8.0, 60.0, &t);
    try std.testing.expectEqual(@as(f64, 0.0), direct);
    try std.testing.expect(made_good > 2.0);

    // Fair wind: made-good equals the straight polar (no offset helps).
    const fair = sailaero.polar.speedAt(kind, plane, 8.0, 135.0, &t);
    const mg_fair = madeGoodSpeed(kind, plane, 8.0, 135.0, &t);
    try std.testing.expect(mg_fair >= fair * 0.999);
}
