//! Print speed polars for the reference sloop and tea clipper.
//! Usage: zig build polar

const std = @import("std");
const rig_mod = @import("rig.zig");
const squarerig = @import("squarerig.zig");
const polar = @import("polar.zig");

fn quadraticTable(comptime n: usize, c: f64, v_max: f64) [n]polar.ResistancePoint {
    var t: [n]polar.ResistancePoint = undefined;
    for (&t, 0..) |*p, i| {
        const v = v_max * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n - 1));
        p.* = .{ .v_mps = v, .r_n = c * v * v };
    }
    return t;
}

pub fn main(init: std.process.Init) !u8 {
    var stdout_buf: [8192]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const w = &stdout_w.interface;

    const sloop: polar.RigKind = .{ .fore_and_aft = rig_mod.testSloop() };
    const sloop_hull = polar.Hull{ .draft_m = 1.8 };
    const sloop_table = quadraticTable(31, 150.0, 15.0);

    const clipper: polar.RigKind = .{ .square = squarerig.testClipper() };
    const clipper_hull = polar.Hull{ .draft_m = 6.0 };
    const clipper_table = quadraticTable(31, 5000.0, 15.0);

    const winds = [_]f64{ 5.0, 8.0, 12.0 };

    try w.writeAll("yard-sailaero speed polars (knots) — ORC 2023 rig coefficients\n");
    try w.writeAll("boat speed at true wind angle, per true wind speed\n\n");
    for ([_][]const u8{ "10 m sloop (35+25 m2, draft 1.8 m)", "tea clipper (3000 m2 square rig, draft 6.0 m)" }, 0..) |name, which| {
        try w.print("{s}\n", .{name});
        try w.writeAll("TWA\\TWS ");
        for (winds) |tws| try w.print("{d:>7.1} m/s", .{tws});
        try w.writeAll("\n");
        var twa: f64 = 30.0;
        while (twa <= 180.0) : (twa += 15.0) {
            try w.print("{d:>5.0}   ", .{twa});
            for (winds) |tws| {
                const v = if (which == 0)
                    polar.speedAt(sloop, sloop_hull, tws, twa, &sloop_table)
                else
                    polar.speedAt(clipper, clipper_hull, tws, twa, &clipper_table);
                try w.print("{d:>10.2}", .{v * 1.9438444924406046});
            }
            try w.writeAll("\n");
        }
        try w.writeAll("\n");
    }
    try w.flush();
    return 0;
}
