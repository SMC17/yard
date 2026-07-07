const std = @import("std");
const yard = @import("yard_bem");

fn nanosSinceBoot() u64 {
    var ts: std.posix.timespec = undefined;
    const clock_gettime = if (@hasDecl(std.posix, "clock_gettime")) std.posix.clock_gettime else std.posix.system.clock_gettime;
    _ = clock_gettime(.MONOTONIC, &ts);
    if (@hasField(std.posix.timespec, "tv_sec")) {
        return @as(u64, @intCast(ts.tv_sec)) * 1_000_000_000 + @as(u64, @intCast(ts.tv_nsec));
    } else {
        return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
    }
}

fn benchCircle(comptime N: usize, iters: usize) !void {
    var panels: [N]yard.hess_smith_2d.Panel = undefined;
    var k: usize = 0;
    while (k < N) : (k += 1) {
        const theta1 = -@as(f64, @floatFromInt(k)) * 2.0 * std.math.pi / @as(f64, @floatFromInt(N));
        const theta2 = -@as(f64, @floatFromInt(k + 1)) * 2.0 * std.math.pi / @as(f64, @floatFromInt(N));
        panels[k] = try yard.hess_smith_2d.buildPanel(@cos(theta1), @sin(theta1), @cos(theta2), @sin(theta2));
    }

    var A: [N * N]f64 = undefined;
    var b: [N]f64 = undefined;

    var accum: f64 = 0.0;
    const start = nanosSinceBoot();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        try yard.hess_smith_2d.assemble(&panels, 1.0 + @as(f64, @floatFromInt(i % 10)) * 1e-9, 0.0, &A, &b);
        try yard.hess_smith_2d.gaussSolve(&A, &b, N);
        accum += b[0];
    }
    const end = nanosSinceBoot();
    std.mem.doNotOptimizeAway(&accum);
    const ns = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iters));
    @import("nats_telemetry.zig").publishPrint("assemble+solve circle N={d:<3}     iters={d:<6}  us/call={d:>7.1}\n", .{ N, iters, ns / 1000.0 });
}

pub fn main() !void {
    @import("nats_telemetry.zig").publishPrint("yard-bem-zig bench (single-thread)\n\n", .{});
    try benchCircle(16, 5000);
    try benchCircle(32, 2000);
    try benchCircle(64, 500);
}
