const std = @import("std");
const yard = @import("yard_maneuvering");

const iters: usize = 1_000_000;

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

pub fn main() !void {
    std.debug.print("yard-maneuvering-zig bench (single-thread)\n\n", .{});
    var accum: f64 = 0.0;

    const start = nanosSinceBoot();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const t = @as(f64, @floatFromInt(i % 100)) * 0.5;
        accum += try yard.nomoto.nomotoFirstOrderYawRate(0.18, 14.0, 0.1745, t);
    }
    const end = nanosSinceBoot();
    std.mem.doNotOptimizeAway(&accum);
    const ns = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iters));
    std.debug.print("nomoto.firstOrderYawRate         iters={d:<8}  ns/call={d:>7.1}\n", .{ iters, ns });
}
