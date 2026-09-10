const std = @import("std");
const yard = @import("yard_resistance");

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

fn fixtureCargo() yard.holtrop.HullParticulars {
    return .{
        .L = 100.0,
        .B = 16.0,
        .T = 6.0,
        .displacement_vol = 8500.0,
        .S = 2500.0,
        .C_B = 0.65,
        .C_M = 0.98,
        .C_P = 0.66,
        .C_WP = 0.78,
        .lcb_pct = -1.0,
        .c_stern = 0.0,
    };
}

pub fn main() !void {
    @import("nats_telemetry.zig").publishPrint("yard-resistance-zig bench (single-thread)\n\n", .{});

    const hp = fixtureCargo();
    const env: yard.holtrop.Environment = .{};
    var accum: f64 = 0.0;

    // ITTC-57 cF
    {
        const start = nanosSinceBoot();
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            const rn = 1.0e6 + @as(f64, @floatFromInt(i % 1000)) * 1.0e6;
            accum += try yard.ittc57.cF(rn);
        }
        const end = nanosSinceBoot();
        std.mem.doNotOptimizeAway(&accum);
        const ns = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iters));
        @import("nats_telemetry.zig").publishPrint("ittc57.cF                        iters={d:<8}  ns/call={d:>7.1}\n", .{ iters, ns });
    }

    // Holtrop form factor
    {
        const start = nanosSinceBoot();
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            var h = hp;
            h.B = 16.0 + @as(f64, @floatFromInt(i % 100)) * 0.001;
            accum += yard.holtrop.formFactor1984(h);
        }
        const end = nanosSinceBoot();
        std.mem.doNotOptimizeAway(&accum);
        const ns = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iters));
        @import("nats_telemetry.zig").publishPrint("holtrop.formFactor1984           iters={d:<8}  ns/call={d:>7.1}\n", .{ iters, ns });
    }

    // Total resistance
    {
        const start = nanosSinceBoot();
        var i: usize = 0;
        while (i < iters) : (i += 1) {
            const v = 4.0 + @as(f64, @floatFromInt(i % 100)) * 0.05;
            accum += (try yard.holtrop.totalResistance(hp, v, env)).r_total;
        }
        const end = nanosSinceBoot();
        std.mem.doNotOptimizeAway(&accum);
        const ns = @as(f64, @floatFromInt(end - start)) / @as(f64, @floatFromInt(iters));
        @import("nats_telemetry.zig").publishPrint("holtrop.totalResistance          iters={d:<8}  ns/call={d:>7.1}\n", .{ iters, ns });
    }
}
