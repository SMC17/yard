// Microbenchmark: Wageningen B-series polynomial evaluation throughput.

const std = @import("std");
const yard = @import("yard_propulsion");

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

fn benchKT() void {
    var accum: f64 = 0.0;
    const start = nanosSinceBoot();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        // Vary J per iteration to defeat constant-folding.
        const j = @as(f64, @floatFromInt(i % 100)) * 0.012;
        accum += yard.wageningen.kT(j, 1.0, 0.70, 4.0);
    }
    const end = nanosSinceBoot();
    std.mem.doNotOptimizeAway(&accum);

    const ns_per_call = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iters));
    @import("nats_telemetry.zig").publishPrint("kT(J,P/D,A_E/A_0,Z)              iters={d:<8}  ns/call={d:>7.1}\n", .{ iters, ns_per_call });
}

fn benchKQ() void {
    var accum: f64 = 0.0;
    const start = nanosSinceBoot();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const j = @as(f64, @floatFromInt(i % 100)) * 0.012;
        accum += yard.wageningen.kQ(j, 1.0, 0.70, 4.0);
    }
    const end = nanosSinceBoot();
    std.mem.doNotOptimizeAway(&accum);

    const ns_per_call = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iters));
    @import("nats_telemetry.zig").publishPrint("kQ(J,P/D,A_E/A_0,Z)              iters={d:<8}  ns/call={d:>7.1}\n", .{ iters, ns_per_call });
}

pub fn main() void {
    @import("nats_telemetry.zig").publishPrint("yard-propulsion-zig bench (single-thread)\n", .{});
    @import("nats_telemetry.zig").publishPrint("Wageningen B-series polynomial evaluation, B4-70 P/D=1.0.\n\n", .{});

    benchKT();
    benchKQ();
}
