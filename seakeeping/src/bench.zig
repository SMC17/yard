const std = @import("std");
const yard = @import("yard_seakeeping");

const iters: usize = 200_000;

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
    std.debug.print("yard-seakeeping-zig bench (single-thread)\n\n", .{});

    var accum: f64 = 0.0;

    {
        const start = nanosSinceBoot();
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            const omega = 0.1 + @as(f64, @floatFromInt(i % 100)) * 0.02;
            accum += yard.spectra.ittcModifiedPM(omega, 4.0, 8.0);
        }
        const end = nanosSinceBoot();
        std.mem.doNotOptimizeAway(&accum);
        const ns = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iters));
        std.debug.print("spectra.ittcModifiedPM           iters={d:<8}  ns/call={d:>7.1}\n", .{ iters, ns });
    }

    {
        const start = nanosSinceBoot();
        var i: usize = 0;
        const inner: usize = 1000;
        while (i < inner) : (i += 1) {
            accum += try yard.moments.momentITTC(0, 4.0, 8.0, 0.01, 4.0, 1001);
        }
        const end = nanosSinceBoot();
        std.mem.doNotOptimizeAway(&accum);
        const ns = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(inner));
        std.debug.print("moments.momentITTC (N=1001)      iters={d:<8}  ns/call={d:>7.1}\n", .{ inner, ns });
    }
}
