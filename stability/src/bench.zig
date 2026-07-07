const std = @import("std");
const yard = @import("yard_stability");

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
    @import("nats_telemetry.zig").publishPrint("yard-stability-zig bench (single-thread)\n\n", .{});

    var accum: f64 = 0.0;

    {
        const start = nanosSinceBoot();
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            const phi = (@as(f64, @floatFromInt(i % 60)) + 1.0) * std.math.pi / 180.0;
            accum += yard.gz.wallSidedGZ(0.6389, 0.8889, phi);
        }
        const end = nanosSinceBoot();
        std.mem.doNotOptimizeAway(&accum);
        const ns = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iters));
        @import("nats_telemetry.zig").publishPrint("gz.wallSidedGZ                   iters={d:<8}  ns/call={d:>7.1}\n", .{ iters, ns });
    }

    {
        var angles: [13]f64 = undefined;
        var gz: [13]f64 = undefined;
        for (&angles, 0..) |*a, i| {
            a.* = @as(f64, @floatFromInt(i * 5)) * std.math.pi / 180.0;
        }
        for (&gz, 0..) |*g, i| {
            g.* = 0.5 * @sin(angles[i] * 90.0 / 40.0);
        }
        const start = nanosSinceBoot();
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            gz[6] += 1e-18;
            const r = try yard.is_code.evaluate(&angles, &gz, 0.3);
            if (r.overall == .pass) accum += 1.0;
        }
        const end = nanosSinceBoot();
        std.mem.doNotOptimizeAway(&accum);
        const ns = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iters));
        @import("nats_telemetry.zig").publishPrint("is_code.evaluate                 iters={d:<8}  ns/call={d:>7.1}\n", .{ iters, ns });
    }
}
