const std = @import("std");
const yard = @import("yard_strength");

const iters: usize = 500_000;

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
    @import("nats_telemetry.zig").publishPrint("yard-strength-zig bench (single-thread)\n\n", .{});

    var accum: f64 = 0.0;

    {
        const start = nanosSinceBoot();
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            const L = 100.0 + @as(f64, @floatFromInt(i % 400));
            accum += try yard.ur_s11.waveCoefficient(L);
        }
        const end = nanosSinceBoot();
        std.mem.doNotOptimizeAway(&accum);
        const ns = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iters));
        @import("nats_telemetry.zig").publishPrint("ur_s11.waveCoefficient           iters={d:<8}  ns/call={d:>7.1}\n", .{ iters, ns });
    }

    {
        const start = nanosSinceBoot();
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            const L = 100.0 + @as(f64, @floatFromInt(i % 400));
            accum += try yard.ur_s11.waveMomentHog(L, 32.0, 0.85, 1.0);
        }
        const end = nanosSinceBoot();
        std.mem.doNotOptimizeAway(&accum);
        const ns = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iters));
        @import("nats_telemetry.zig").publishPrint("ur_s11.waveMomentHog             iters={d:<8}  ns/call={d:>7.1}\n", .{ iters, ns });
    }
}
