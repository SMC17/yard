//! Full preliminary vessel assessment: stability + resistance at one speed.

const std = @import("std");
const compose = @import("yard_compose");
const naval = @import("yard_naval_arch");

pub fn main(init: std.process.Init) !u8 {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const out = try compose.vessel_assessment.evaluate(arena.allocator(), .{
        .stability = .{
            .particulars = .{ .L = 10.0, .B = 4.0, .T = 1.5 },
            .loading = .{
                .kg_m = 1.0,
                .tanks = &[_]naval.TankSpec{
                    .{ .l_m = 5.0, .b_m = 3.0, .rho_fluid = 1000.0 },
                },
            },
        },
        .resistance = .{
            .hull = compose.cargo_resistance.CargoFixture.hullParticulars(),
            .speed_mps = 8.0,
        },
    });

    var stdout_buf: [8192]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const w = &stdout_w.interface;
    defer w.flush() catch {};

    try w.print("=== Yard: Full Vessel Assessment (Phase 1) ===\n\n", .{});

    try w.print("--- Stability ---\n", .{});
    try w.print("  GM corrected:  {d:.4} m\n", .{out.stability.stability.gm_corrected_m});
    try w.print("  IS Code:       {}\n\n", .{out.stability.is_code.overall});

    try w.print("--- Resistance @ {d:.1} m/s ---\n", .{out.resistance.speed_mps});
    try w.print("  Fn = {d:.4}  Rn = {e:.2}\n", .{ out.resistance.froude, out.resistance.reynolds });
    try w.print("  R_total = {d:.1} N\n\n", .{out.resistance.r_total});

    try w.print("Proof level: unit-tested (not class-society grade)\n", .{});
    return 0;
}

test "full vessel assessment compiles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try compose.vessel_assessment.evaluate(arena.allocator(), .{
        .stability = .{
            .particulars = .{ .L = 10.0, .B = 4.0, .T = 1.5 },
            .loading = .{ .kg_m = 1.0, .tanks = &.{} },
        },
        .resistance = .{
            .hull = compose.cargo_resistance.CargoFixture.hullParticulars(),
            .speed_mps = 8.0,
        },
    });
    try std.testing.expect(out.resistance.r_total > 0);
}