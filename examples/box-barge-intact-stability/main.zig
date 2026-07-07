//! Canonical box-barge intact stability example.
//! Demonstrates the full hydro → stability → IS Code 2.2 composition chain.

const std = @import("std");
const compose = @import("yard_compose");
const naval = @import("yard_naval_arch");

pub fn main(init: std.process.Init) !u8 {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input: compose.box_barge.Input = .{
        .particulars = .{ .L = 10.0, .B = 4.0, .T = 1.5 },
        .loading = .{
            .kg_m = 1.0,
            .tanks = &[_]naval.TankSpec{
                .{ .l_m = 5.0, .b_m = 3.0, .rho_fluid = 1000.0 },
            },
        },
    };

    const out = try compose.box_barge.evaluate(allocator, input);

    var stdout_buf: [8192]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const w = &stdout_w.interface;
    defer w.flush() catch {};

    try w.print("=== Yard: Box-Barge Intact Stability ===\n\n", .{});
    try w.print("Principal particulars: L={d:.1} m  B={d:.1} m  T={d:.1} m\n", .{
        input.particulars.L, input.particulars.B, input.particulars.T,
    });
    try w.print("Loading: KG={d:.3} m  tanks={d}\n\n", .{ input.loading.kg_m, input.loading.tanks.len });

    try w.print("--- Hydrostatics ---\n", .{});
    try w.print("  Volume:        {d:.3} m³\n", .{out.hydrostatics.volume_m3});
    try w.print("  Displacement:  {d:.1} kg\n", .{out.hydrostatics.displacement_kg});
    try w.print("  KB:            {d:.4} m\n", .{out.hydrostatics.kb_m});
    try w.print("  BM_T:          {d:.4} m\n", .{out.hydrostatics.bm_t_m});
    try w.print("  KM_T:          {d:.4} m\n", .{out.hydrostatics.km_t_m});
    try w.print("  C_B:           {d:.4}\n\n", .{out.hydrostatics.c_b});

    try w.print("--- Stability ---\n", .{});
    try w.print("  GM₀:           {d:.4} m\n", .{out.stability.gm0_m});
    try w.print("  GG' (FS):      {d:.4} m\n", .{out.stability.gg_prime_m});
    try w.print("  GM corrected:  {d:.4} m\n", .{out.stability.gm_corrected_m});
    try w.print("  Wall-sided OK: {}\n\n", .{out.stability.wall_sided_valid});

    try w.print("--- GZ Curve (wall-sided) ---\n", .{});
    for (out.gz_curve) |s| {
        try w.print("  φ = {d:>5.0}°  GZ = {d:.4} m\n", .{ s.angle_deg, s.gz_m });
    }
    try w.print("\n", .{});

    try w.print("--- IMO IS Code 2008 Part A 2.2 ---\n", .{});
    try w.print("  Area 0-30°:    {}  ({d:.4} m·rad)\n", .{ out.is_code.area_0_30, out.is_code.values.area_0_30 });
    try w.print("  Area 0-40°:    {}  ({d:.4} m·rad)\n", .{ out.is_code.area_0_40, out.is_code.values.area_0_40 });
    try w.print("  Area 30-40°:   {}  ({d:.4} m·rad)\n", .{ out.is_code.area_30_40, out.is_code.values.area_30_40 });
    try w.print("  GZ at 30°:     {}  ({d:.4} m)\n", .{ out.is_code.gz_at_30, out.is_code.values.gz_at_30 });
    try w.print("  Angle GZ_max:  {}  ({d:.1}°)\n", .{ out.is_code.angle_gz_max, out.is_code.values.angle_gz_max_deg });
    try w.print("  GM₀:           {}  ({d:.4} m)\n", .{ out.is_code.gm_0, out.is_code.values.gm_0 });
    try w.print("  OVERALL:       {}\n\n", .{out.is_code.overall});

    try w.print("--- Validity Flags ---\n", .{});
    if (out.flags.contains(.wall_sided_assumption_valid))
        try w.print("  ✓ wall_sided_assumption_valid\n", .{});
    if (out.flags.contains(.free_surface_applied))
        try w.print("  ✓ free_surface_applied\n", .{});
    if (out.flags.contains(.small_angle_regime))
        try w.print("  ✓ small_angle_regime\n", .{});

    try w.print("\nProof level: unit-tested\n", .{});
    try w.print("Oracle: yard-stability + yard-hydro (Zig)\n", .{});
    return 0;
}

test "example main compiles and runs workflow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const input: compose.box_barge.Input = .{
        .particulars = .{ .L = 10.0, .B = 4.0, .T = 1.5 },
        .loading = .{ .kg_m = 1.0, .tanks = &.{} },
    };
    const out = try compose.box_barge.evaluate(arena.allocator(), input);
    try std.testing.expect(out.hydrostatics.volume_m3 > 0);
}