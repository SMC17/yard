const std = @import("std");
const yard = @import("yard_ittc78");

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
    @import("nats_telemetry.zig").publishPrint("yard-ittc78-zig bench (single-thread)\n\n", .{});
    var accum: f64 = 0.0;

    const m = yard.chain.ModelScale{ .L = 6.0, .S = 6.5, .V = 1.5, .nu = 1.139e-6, .C_T = 0.0042, .rho = 1000.0 };
    var s = yard.chain.ShipScale{ .L = 150.0, .S = 4000.0, .V = 7.5, .nu = 1.188e-6, .rho = 1025.0 };
    const f = yard.chain.PropulsionFactors{ .one_plus_k = 1.15, .w = 0.3, .t = 0.18, .eta_R = 1.0, .eta_S = 0.98 };
    const p = yard.chain.Propeller{ .D = 4.5, .n_s = 2.0, .K_T_s = 0.18, .K_Q_s = 0.028 };

    const start = nanosSinceBoot();
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        s.V = 5.0 + @as(f64, @floatFromInt(i % 100)) * 0.05;
        const r = try yard.chain.extrapolate(m, s, f, p);
        accum += r.P_E_ship;
    }
    const end = nanosSinceBoot();
    std.mem.doNotOptimizeAway(&accum);
    const ns = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iters));
    @import("nats_telemetry.zig").publishPrint("chain.extrapolate (full 11-step) iters={d:<8}  ns/call={d:>7.1}\n", .{ iters, ns });
}
