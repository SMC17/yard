//! oceanman_smoke_main.zig: driver for `scripts/oceanman_smoke.sh`.
//!
//! Usage:
//!   oceanman-smoke <cable-json-path> [landing-point-geo-path]
//!
//! Reads the cable record + optional landing-point FeatureCollection,
//! emits a LayPlan to stdout, and prints the parse time (microseconds)
//! to stderr. Exit non-zero on parse failure.

const std = @import("std");
const Io = std.Io;
const yard = @import("yard_pipeline");
const consumer = yard.cable_route_consumer;

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;

    var args_buf: std.ArrayList([]const u8) = .empty;
    defer args_buf.deinit(allocator);

    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    while (it.next()) |a| try args_buf.append(allocator, a);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_w.interface;
    defer stdout.flush() catch {};

    var stderr_buf: [4096]u8 = undefined;
    var stderr_w = std.Io.File.stderr().writer(init.io, &stderr_buf);
    const stderr = &stderr_w.interface;
    defer stderr.flush() catch {};

    if (args_buf.items.len < 2) {
        try stderr.print("usage: {s} <cable-json-path> [landing-point-geo-path]\n", .{args_buf.items[0]});
        return 2;
    }
    const cable_path = args_buf.items[1];
    const landing_path: ?[]const u8 = if (args_buf.items.len >= 3) args_buf.items[2] else null;

    // Slurp the cable record.
    const cable_bytes = readFileAll(allocator, init.io, cable_path) catch |err| {
        try stderr.print("error: cannot read cable file {s}: {s}\n", .{ cable_path, @errorName(err) });
        return 1;
    };
    defer allocator.free(cable_bytes);

    var coord_index_storage: ?consumer.CoordIndex = null;
    defer if (coord_index_storage) |*ci| ci.deinit(allocator);
    var coord_index_ptr: ?*const consumer.CoordIndex = null;

    if (landing_path) |lp| {
        const landing_bytes = readFileAll(allocator, init.io, lp) catch |err| {
            try stderr.print("error: cannot read landing-point-geo {s}: {s}\n", .{ lp, @errorName(err) });
            return 1;
        };
        defer allocator.free(landing_bytes);
        coord_index_storage = consumer.loadCoordIndexFromJson(allocator, landing_bytes) catch |err| {
            try stderr.print("error: cannot parse landing-point-geo: {s}\n", .{@errorName(err)});
            return 1;
        };
        coord_index_ptr = &coord_index_storage.?;
    }

    const t0 = Io.Clock.boot.now(init.io);
    var plan = consumer.consumeCableJson(allocator, cable_bytes, coord_index_ptr) catch |err| {
        try stderr.print("error: cannot parse cable record: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer plan.deinit(allocator);
    const t1 = Io.Clock.boot.now(init.io);

    try consumer.writeLayPlan(&plan, stdout);

    const elapsed_ns: i96 = t0.durationTo(t1).nanoseconds;
    const elapsed_us: f64 = @as(f64, @floatFromInt(@as(i64, @intCast(elapsed_ns)))) / 1000.0;
    try stderr.print("parse_us={d:.3} waypoints={d} with_coords={d}\n", .{
        elapsed_us, plan.waypoints.len, plan.waypoints_with_coords,
    });
    return 0;
}

fn readFileAll(allocator: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    var f = try Io.Dir.cwd().openFile(io, path, .{});
    defer f.close(io);
    const st = try f.stat(io);
    const buf = try allocator.alloc(u8, st.size);
    errdefer allocator.free(buf);
    var read_buf: [4096]u8 = undefined;
    var reader = f.reader(io, &read_buf);
    var iface = &reader.interface;
    var off: usize = 0;
    while (off < buf.len) {
        const n = try iface.readSliceShort(buf[off..]);
        if (n == 0) break;
        off += n;
    }
    return buf[0..off];
}
