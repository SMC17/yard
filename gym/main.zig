//! CLI for Python ctypes/subprocess bridge: emit JSON for L0/L1.
//! Modes: l0 | l1 | l1_hm1984 | both | both_hm1984
const std = @import("std");
const gym = @import("root.zig");

fn writeL1(stdout: anytype, r: gym.ResistanceResult, fidelity: []const u8) !void {
    try stdout.writeAll(",\"l1\":{");
    try stdout.print("\"Fn\":{d:.12},\"Rn\":{d:.12},\"Cf\":{d:.12},\"k1\":{d:.12},\"Cw\":{d:.12},\"Rt_N\":{d:.12},\"Ct\":{d:.12},\"fidelity\":\"{s}\"", .{
        r.Fn, r.Rn, r.Cf, r.k1, r.Cw, r.Rt_N, r.Ct, fidelity,
    });
    try stdout.writeAll("}");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // exe

    var mode: []const u8 = "both";
    var h: gym.Hull = .{};

    // Optional: mode then 7 floats: L B T Cb lcb_frac kg_frac Fn
    if (args.next()) |m| {
        if (std.mem.eql(u8, m, "l0") or std.mem.eql(u8, m, "l1") or std.mem.eql(u8, m, "l1_hm1984") or
            std.mem.eql(u8, m, "both") or std.mem.eql(u8, m, "both_hm1984") or
            std.mem.eql(u8, m, "hm1984"))
        {
            mode = if (std.mem.eql(u8, m, "hm1984")) "l1_hm1984" else m;
            if (args.next()) |s| h.L = try std.fmt.parseFloat(f64, s);
        } else {
            h.L = try std.fmt.parseFloat(f64, m);
        }
    }
    if (args.next()) |s| h.B = try std.fmt.parseFloat(f64, s);
    if (args.next()) |s| h.T = try std.fmt.parseFloat(f64, s);
    if (args.next()) |s| h.Cb = try std.fmt.parseFloat(f64, s);
    if (args.next()) |s| h.lcb_frac = try std.fmt.parseFloat(f64, s);
    if (args.next()) |s| h.kg_frac = try std.fmt.parseFloat(f64, s);
    if (args.next()) |s| h.Fn = try std.fmt.parseFloat(f64, s);

    var out_buf: [4096]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&out_buf);
    const stdout = &file_writer.interface;
    try stdout.writeAll("{");
    try stdout.print("\"L\":{d:.10},\"B\":{d:.10},\"T\":{d:.10},\"Cb\":{d:.10},\"lcb_frac\":{d:.10},\"kg_frac\":{d:.10},\"Fn\":{d:.10}", .{
        h.L, h.B, h.T, h.Cb, h.lcb_frac, h.kg_frac, h.Fn,
    });

    const want_l0 = std.mem.eql(u8, mode, "l0") or std.mem.eql(u8, mode, "both") or std.mem.eql(u8, mode, "both_hm1984");
    const want_l1_simp = std.mem.eql(u8, mode, "l1") or std.mem.eql(u8, mode, "both");
    const want_l1_hm = std.mem.eql(u8, mode, "l1_hm1984") or std.mem.eql(u8, mode, "both_hm1984");

    if (want_l0) {
        const r = gym.evaluate_l0(h);
        try stdout.writeAll(",\"l0\":{");
        try stdout.print("\"feasible\":{},\"gm0_m\":{d:.12},\"volume_m3\":{d:.12},\"displacement_t\":{d:.12},\"L_B\":{d:.12},\"T_B\":{d:.12},\"Cb\":{d:.12}", .{
            r.feasible, r.gm0_m, r.volume_m3, r.displacement_t, r.L_B, r.T_B, r.Cb,
        });
        try stdout.writeAll(",\"violations\":[");
        var i: usize = 0;
        while (i < r.n_violations) : (i += 1) {
            if (i > 0) try stdout.writeAll(",");
            try stdout.print("\"{s}\"", .{r.violations[i]});
        }
        try stdout.writeAll("]}");
    }

    if (want_l1_simp) {
        const r = gym.estimate_resistance(h);
        try writeL1(stdout, r, "L1_holtrop_simplified");
    }

    if (want_l1_hm) {
        const r = gym.estimate_resistance_hm1984(h) catch {
            try stdout.writeAll(",\"l1\":{\"error\":\"hm1984_failed\",\"fidelity\":\"L1_holtrop_hm1984\"}");
            try stdout.writeAll("}\n");
            try stdout.flush();
            return;
        };
        try writeL1(stdout, r, "hm1984_zig");
    }

    try stdout.writeAll("}\n");
    try stdout.flush();
}
