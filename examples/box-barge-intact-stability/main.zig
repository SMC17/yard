//! Canonical box-barge intact stability example.
//! Demonstrates the full hydro → stability → IS Code 2.2 composition chain.
//! Pass `--envelope` to emit Sovereign Experience ArtifactEnvelope JSON.

const std = @import("std");
const compose = @import("yard_compose");
const naval = @import("yard_naval_arch");

pub fn main(init: std.process.Init) !u8 {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var envelope_mode = false;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--envelope")) envelope_mode = true;
    }

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

    var stdout_buf: [16384]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const w = &stdout_w.interface;
    defer w.flush() catch {};

    if (envelope_mode) {
        try emitEnvelopes(w, &out);
        return 0;
    }

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
    try w.print("Envelope JSON: zig build run -- --envelope\n", .{});
    return 0;
}

fn emitEnvelopes(w: anytype, out: anytype) !void {
    const overall_auth: []const u8 = if (out.is_code.overall == .pass) "unit-tested" else "refuted";
    try w.print("{{\"schema\":\"sovereign.yard.box-barge-envelopes.v0\",\"plane\":\"assurance\",\"operational_qualification_claimed\":false,\"source\":\"yard/examples/box-barge-intact-stability\",\"particulars\":{{\"L\":10.0,\"B\":4.0,\"T\":1.5,\"KG\":1.0}},\"envelopes\":[", .{});

    try w.print("{{\"schema\":\"sovereign.artifact-envelope.v0\",\"id\":\"yard-box-barge-gm0\",\"kind\":\"scalar\",\"schema_version\":\"0\",\"value\":{d:.6},\"units\":{{\"symbol\":\"m\",\"system\":\"si\"}},\"generated_at\":\"2026-07-12T00:00:00Z\",\"source\":{{\"engine\":\"yard-compose/box_barge\",\"engine_version\":\"0.0.0\",\"model\":\"box-barge-intact\",\"model_version\":\"canonical-10x4x1.5\"}},\"context\":{{\"intended_use\":\"intact_stability_assessment\",\"scenario_id\":\"box-barge-canonical\",\"run_id\":\"box-barge-envelope-001\"}},\"validity\":{{\"status\":\"inside-envelope\",\"constraints\":[\"IS Code GM0 >= 0.15 m\"]}},\"authority\":{{\"level\":\"{s}\",\"evidence_ids\":[\"yard-stability-is-code\",\"yard-hydro-box-barge\"]}},\"operational_qualification_claimed\":false}},", .{ out.stability.gm0_m, overall_auth });

    try w.print("{{\"schema\":\"sovereign.artifact-envelope.v0\",\"id\":\"yard-box-barge-gm-corrected\",\"kind\":\"scalar\",\"schema_version\":\"0\",\"value\":{d:.6},\"units\":{{\"symbol\":\"m\",\"system\":\"si\"}},\"generated_at\":\"2026-07-12T00:00:00Z\",\"source\":{{\"engine\":\"yard-compose/box_barge\",\"engine_version\":\"0.0.0\",\"model\":\"box-barge-intact\",\"model_version\":\"canonical-10x4x1.5\"}},\"context\":{{\"intended_use\":\"intact_stability_assessment\",\"scenario_id\":\"box-barge-canonical\",\"run_id\":\"box-barge-envelope-001\"}},\"validity\":{{\"status\":\"inside-envelope\",\"constraints\":[\"free_surface_applied\"]}},\"authority\":{{\"level\":\"unit-tested\",\"evidence_ids\":[\"yard-stability-fs\"]}},\"operational_qualification_claimed\":false}},", .{out.stability.gm_corrected_m});

    try w.print("{{\"schema\":\"sovereign.artifact-envelope.v0\",\"id\":\"yard-box-barge-area-0-30\",\"kind\":\"scalar\",\"schema_version\":\"0\",\"value\":{d:.6},\"units\":{{\"symbol\":\"m·rad\",\"system\":\"si\"}},\"generated_at\":\"2026-07-12T00:00:00Z\",\"source\":{{\"engine\":\"yard-compose/box_barge\",\"engine_version\":\"0.0.0\",\"model\":\"imo-is-code-2008-a-2.2\",\"model_version\":\"MSC.267(85)\"}},\"context\":{{\"intended_use\":\"intact_stability_assessment\",\"scenario_id\":\"box-barge-canonical\",\"run_id\":\"box-barge-envelope-001\"}},\"validity\":{{\"status\":\"inside-envelope\",\"constraints\":[\"required >= 0.055 m·rad\",\"verdict={s}\"]}},\"authority\":{{\"level\":\"unit-tested\",\"evidence_ids\":[\"imo-is-code-2008\"]}},\"operational_qualification_claimed\":false}},", .{ out.is_code.values.area_0_30, @tagName(out.is_code.area_0_30) });

    try w.print("{{\"schema\":\"sovereign.artifact-envelope.v0\",\"id\":\"yard-box-barge-gz-30\",\"kind\":\"scalar\",\"schema_version\":\"0\",\"value\":{d:.6},\"units\":{{\"symbol\":\"m\",\"system\":\"si\"}},\"generated_at\":\"2026-07-12T00:00:00Z\",\"source\":{{\"engine\":\"yard-compose/box_barge\",\"engine_version\":\"0.0.0\",\"model\":\"wall-sided-gz\",\"model_version\":\"atwood\"}},\"context\":{{\"intended_use\":\"intact_stability_assessment\",\"scenario_id\":\"box-barge-canonical\",\"run_id\":\"box-barge-envelope-001\"}},\"validity\":{{\"status\":\"inside-envelope\",\"constraints\":[\"required >= 0.200 m\",\"verdict={s}\"]}},\"authority\":{{\"level\":\"unit-tested\",\"evidence_ids\":[\"imo-is-code-2008\"]}},\"operational_qualification_claimed\":false}},", .{ out.is_code.values.gz_at_30, @tagName(out.is_code.gz_at_30) });

    try w.print("{{\"schema\":\"sovereign.artifact-envelope.v0\",\"id\":\"yard-box-barge-gz-curve\",\"kind\":\"timeseries\",\"schema_version\":\"0\",\"value\":{{\"angles_deg\":[", .{});
    for (out.gz_curve, 0..) |s, i| {
        if (i != 0) try w.print(",", .{});
        try w.print("{d:.0}", .{s.angle_deg});
    }
    try w.print("],\"gz_m\":[", .{});
    for (out.gz_curve, 0..) |s, i| {
        if (i != 0) try w.print(",", .{});
        try w.print("{d:.6}", .{s.gz_m});
    }
    try w.print("]}},\"units\":{{\"symbol\":\"m\",\"system\":\"si\"}},\"generated_at\":\"2026-07-12T00:00:00Z\",\"source\":{{\"engine\":\"yard-compose/box_barge\",\"engine_version\":\"0.0.0\",\"model\":\"wall-sided-gz\",\"model_version\":\"atwood\"}},\"context\":{{\"intended_use\":\"intact_stability_assessment\",\"scenario_id\":\"box-barge-canonical\",\"run_id\":\"box-barge-envelope-001\"}},\"validity\":{{\"status\":\"inside-envelope\",\"constraints\":[\"wall_sided_assumption_valid\"]}},\"uncertainty\":{{\"type\":\"qualitative\",\"payload\":{{\"note\":\"wall-sided Atwood; not general hull offsets\"}}}},\"authority\":{{\"level\":\"unit-tested\",\"evidence_ids\":[\"yard-stability-gz\"]}},\"operational_qualification_claimed\":false}}", .{});

    try w.print("],\"is_code_overall\":\"{s}\"}}\n", .{@tagName(out.is_code.overall)});
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
