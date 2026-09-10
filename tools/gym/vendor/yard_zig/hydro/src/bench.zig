// Microbenchmark: yard-hydro-zig integration throughput.
//
// Measures per-call latency of Simpson 1/3 on Wigley waterline ordinates for
// representative station counts. Honest single-thread numbers; reports
// nanoseconds per call. No claims of "fast" or "production-grade"; just the
// number, the load tag, and the build flags.

const std = @import("std");
const yard = @import("yard_hydro");

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

fn bench(name: []const u8, comptime N: usize) !void {
    const h = yard.wigley.Hull{ .L = 100.0, .B = 10.0, .T = 4.0 };
    var ords: [N]f64 = undefined;
    h.waterlineOrdinates(0.0, &ords);
    const dx = h.L / @as(f64, @floatFromInt(N - 1));

    var accum: f64 = 0.0;
    const start = nanosSinceBoot();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        // Per-iteration write defeats constant-folding on loop-invariant ordinates.
        // The perturbation is far below f64 precision at typical ordinate
        // magnitudes (~5 m); it does not affect correctness, only defeats hoisting.
        ords[i % N] += 1e-30;
        const v = try yard.simpson.simpson13(&ords, dx);
        accum += v;
    }
    const end = nanosSinceBoot();
    std.mem.doNotOptimizeAway(&accum);
    std.mem.doNotOptimizeAway(&ords);

    const elapsed_ns = end - start;
    const ns_per_call = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iters));
    @import("nats_telemetry.zig").publishPrint(
        "{s:<24} N={d:<4}  iters={d:<8}  ns/call={d:>8.1}  accum={e}\n",
        .{ name, N, iters, ns_per_call, accum },
    );
}

pub fn main() !void {
    @import("nats_telemetry.zig").publishPrint("yard-hydro-zig bench (single-thread)\n", .{});
    @import("nats_telemetry.zig").publishPrint("Wigley waterline integration; Simpson 1/3 on N stations.\n\n", .{});

    try bench("simpson13_wigley", 11);
    try bench("simpson13_wigley", 21);
    try bench("simpson13_wigley", 41);
    try bench("simpson13_wigley", 81);
    try bench("simpson13_wigley", 161);
    try bench("simpson13_wigley", 321);
}
