//! Box-barge intact stability example with loading CLI + named cases.
//!
//! ```
//! zig build run -- --case canonical --envelope
//! zig build run -- --case coastal-feeder --envelope
//! zig build run -- --L 12 --B 5 --T 1.8 --KG 1.1 --tank 6x3.5 --envelope
//! zig build run -- --case canonical --no-tank
//! ```

const std = @import("std");
const compose = @import("yard_compose");
const naval = @import("yard_naval_arch");

const Case = struct {
    id: []const u8,
    L: f64,
    B: f64,
    T: f64,
    kg_m: f64,
    tank_l: ?f64,
    tank_b: ?f64,
    tank_rho: f64,
};

const cases = [_]Case{
    .{
        .id = "canonical",
        .L = 10.0,
        .B = 4.0,
        .T = 1.5,
        .kg_m = 1.0,
        .tank_l = 5.0,
        .tank_b = 3.0,
        .tank_rho = 1000.0,
    },
    .{
        // Second hull/loading: longer coastal feeder barge, higher KG, larger FS tank.
        .id = "coastal-feeder",
        .L = 24.0,
        .B = 8.0,
        .T = 2.5,
        .kg_m = 1.8,
        .tank_l = 8.0,
        .tank_b = 4.0,
        .tank_rho = 1000.0,
    },
};

fn usage() void {
    std.debug.print(
        \\usage: box-barge-intact-stability [options]
        \\  --case canonical|coastal-feeder   named hull/loading (default: canonical)
        \\  --L m --B m --T m --KG m          override particulars / loading
        \\  --tank LxB[@rho]                  rectangular FS tank (rho default 1000)
        \\  --no-tank                         clear tanks
        \\  --envelope                        emit ArtifactEnvelope JSON
        \\  --help
        \\
    , .{});
}

fn parseF64(s: []const u8) !f64 {
    return std.fmt.parseFloat(f64, s);
}

fn parseTank(spec: []const u8, l: *f64, b: *f64, rho: *f64) !void {
    // forms: 5x3   or 5x3@1025
    var rest = spec;
    var rho_part: ?[]const u8 = null;
    if (std.mem.indexOfScalar(u8, spec, '@')) |at| {
        rest = spec[0..at];
        rho_part = spec[at + 1 ..];
    }
    const x = std.mem.indexOfScalar(u8, rest, 'x') orelse return error.BadTankSpec;
    l.* = try parseF64(rest[0..x]);
    b.* = try parseF64(rest[x + 1 ..]);
    if (rho_part) |rp| rho.* = try parseF64(rp);
}

pub fn main(init: std.process.Init) !u8 {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var envelope_mode = false;
    var case_id: []const u8 = "canonical";
    var L: ?f64 = null;
    var B: ?f64 = null;
    var T: ?f64 = null;
    var KG: ?f64 = null;
    var tank_set = false;
    var no_tank = false;
    var tank_l: f64 = 5.0;
    var tank_b: f64 = 3.0;
    var tank_rho: f64 = 1000.0;

    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            usage();
            return 0;
        } else if (std.mem.eql(u8, arg, "--envelope")) {
            envelope_mode = true;
        } else if (std.mem.eql(u8, arg, "--no-tank")) {
            no_tank = true;
            tank_set = true;
        } else if (std.mem.eql(u8, arg, "--case")) {
            case_id = it.next() orelse {
                usage();
                return 2;
            };
        } else if (std.mem.eql(u8, arg, "--L")) {
            L = try parseF64(it.next() orelse return 2);
        } else if (std.mem.eql(u8, arg, "--B")) {
            B = try parseF64(it.next() orelse return 2);
        } else if (std.mem.eql(u8, arg, "--T")) {
            T = try parseF64(it.next() orelse return 2);
        } else if (std.mem.eql(u8, arg, "--KG")) {
            KG = try parseF64(it.next() orelse return 2);
        } else if (std.mem.eql(u8, arg, "--tank")) {
            const spec = it.next() orelse return 2;
            try parseTank(spec, &tank_l, &tank_b, &tank_rho);
            tank_set = true;
            no_tank = false;
        } else {
            std.debug.print("unknown arg: {s}\n", .{arg});
            usage();
            return 2;
        }
    }

    const base = blk: {
        for (cases) |c| {
            if (std.mem.eql(u8, c.id, case_id)) break :blk c;
        }
        std.debug.print("unknown --case {s} (canonical|coastal-feeder)\n", .{case_id});
        return 2;
    };

    const use_L = L orelse base.L;
    const use_B = B orelse base.B;
    const use_T = T orelse base.T;
    const use_KG = KG orelse base.kg_m;

    var tank_storage: [1]naval.TankSpec = undefined;
    var tanks_slice: []const naval.TankSpec = &.{};
    if (!no_tank) {
        const tl = if (tank_set) tank_l else (base.tank_l orelse 0);
        const tb = if (tank_set) tank_b else (base.tank_b orelse 0);
        const tr = if (tank_set) tank_rho else base.tank_rho;
        if (base.tank_l != null or tank_set) {
            tank_storage[0] = .{ .l_m = tl, .b_m = tb, .rho_fluid = tr };
            tanks_slice = tank_storage[0..1];
        }
    }

    const input: compose.box_barge.Input = .{
        .particulars = .{ .L = use_L, .B = use_B, .T = use_T },
        .loading = .{ .kg_m = use_KG, .tanks = tanks_slice },
    };

    const out = try compose.box_barge.evaluate(allocator, input);

    var stdout_buf: [32768]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const w = &stdout_w.interface;
    defer w.flush() catch {};

    const meta = EnvelopeMeta{
        .case_id = case_id,
        .L = use_L,
        .B = use_B,
        .T = use_T,
        .KG = use_KG,
        .tank_count = tanks_slice.len,
    };

    if (envelope_mode) {
        try emitEnvelopes(w, &out, meta);
        return 0;
    }

    try w.print("=== Yard: Box-Barge Intact Stability ===\n", .{});
    try w.print("Case: {s}\n\n", .{case_id});
    try w.print("Principal particulars: L={d:.1} m  B={d:.1} m  T={d:.1} m\n", .{ use_L, use_B, use_T });
    try w.print("Loading: KG={d:.3} m  tanks={d}\n\n", .{ use_KG, tanks_slice.len });

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

    try w.print("--- GZ Curve ---\n", .{});
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

    try w.print("Proof level: unit-tested\n", .{});
    return 0;
}

const EnvelopeMeta = struct {
    case_id: []const u8,
    L: f64,
    B: f64,
    T: f64,
    KG: f64,
    tank_count: usize,
};

fn emitEnvelopes(w: anytype, out: anytype, meta: EnvelopeMeta) !void {
    const overall_auth: []const u8 = if (out.is_code.overall == .pass) "unit-tested" else "refuted";
    const model_ver = meta.case_id;
    try w.print(
        "{{\"schema\":\"sovereign.yard.box-barge-envelopes.v0\",\"plane\":\"assurance\",\"operational_qualification_claimed\":false,\"source\":\"yard/examples/box-barge-intact-stability\",\"case_id\":\"{s}\",\"particulars\":{{\"L\":{d:.6},\"B\":{d:.6},\"T\":{d:.6},\"KG\":{d:.6},\"tank_count\":{d}}},\"envelopes\":[",
        .{ meta.case_id, meta.L, meta.B, meta.T, meta.KG, meta.tank_count },
    );

    try w.print("{{\"schema\":\"sovereign.artifact-envelope.v0\",\"id\":\"yard-box-barge-gm0\",\"kind\":\"scalar\",\"schema_version\":\"0\",\"value\":{d:.6},\"units\":{{\"symbol\":\"m\",\"system\":\"si\"}},\"generated_at\":\"2026-07-12T01:00:00Z\",\"source\":{{\"engine\":\"yard-compose/box_barge\",\"engine_version\":\"0.0.0\",\"model\":\"box-barge-intact\",\"model_version\":\"{s}\"}},\"context\":{{\"intended_use\":\"intact_stability_assessment\",\"scenario_id\":\"{s}\",\"run_id\":\"box-barge-envelope-{s}\"}},\"validity\":{{\"status\":\"inside-envelope\",\"constraints\":[\"IS Code GM0 >= 0.15 m\"]}},\"authority\":{{\"level\":\"{s}\",\"evidence_ids\":[\"yard-stability-is-code\",\"yard-hydro-box-barge\"]}},\"operational_qualification_claimed\":false}},", .{ out.stability.gm0_m, model_ver, meta.case_id, meta.case_id, overall_auth });

    try w.print("{{\"schema\":\"sovereign.artifact-envelope.v0\",\"id\":\"yard-box-barge-gm-corrected\",\"kind\":\"scalar\",\"schema_version\":\"0\",\"value\":{d:.6},\"units\":{{\"symbol\":\"m\",\"system\":\"si\"}},\"generated_at\":\"2026-07-12T01:00:00Z\",\"source\":{{\"engine\":\"yard-compose/box_barge\",\"engine_version\":\"0.0.0\",\"model\":\"box-barge-intact\",\"model_version\":\"{s}\"}},\"context\":{{\"intended_use\":\"intact_stability_assessment\",\"scenario_id\":\"{s}\",\"run_id\":\"box-barge-envelope-{s}\"}},\"validity\":{{\"status\":\"inside-envelope\",\"constraints\":[\"free_surface_applied_or_absent\"]}},\"authority\":{{\"level\":\"unit-tested\",\"evidence_ids\":[\"yard-stability-fs\"]}},\"operational_qualification_claimed\":false}},", .{ out.stability.gm_corrected_m, model_ver, meta.case_id, meta.case_id });

    try w.print("{{\"schema\":\"sovereign.artifact-envelope.v0\",\"id\":\"yard-box-barge-area-0-30\",\"kind\":\"scalar\",\"schema_version\":\"0\",\"value\":{d:.6},\"units\":{{\"symbol\":\"m·rad\",\"system\":\"si\"}},\"generated_at\":\"2026-07-12T01:00:00Z\",\"source\":{{\"engine\":\"yard-compose/box_barge\",\"engine_version\":\"0.0.0\",\"model\":\"imo-is-code-2008-a-2.2\",\"model_version\":\"{s}\"}},\"context\":{{\"intended_use\":\"intact_stability_assessment\",\"scenario_id\":\"{s}\",\"run_id\":\"box-barge-envelope-{s}\"}},\"validity\":{{\"status\":\"inside-envelope\",\"constraints\":[\"required >= 0.055 m·rad\",\"verdict={s}\"]}},\"authority\":{{\"level\":\"unit-tested\",\"evidence_ids\":[\"imo-is-code-2008\"]}},\"operational_qualification_claimed\":false}},", .{ out.is_code.values.area_0_30, model_ver, meta.case_id, meta.case_id, @tagName(out.is_code.area_0_30) });

    try w.print("{{\"schema\":\"sovereign.artifact-envelope.v0\",\"id\":\"yard-box-barge-gz-30\",\"kind\":\"scalar\",\"schema_version\":\"0\",\"value\":{d:.6},\"units\":{{\"symbol\":\"m\",\"system\":\"si\"}},\"generated_at\":\"2026-07-12T01:00:00Z\",\"source\":{{\"engine\":\"yard-compose/box_barge\",\"engine_version\":\"0.0.0\",\"model\":\"wall-sided-gz\",\"model_version\":\"{s}\"}},\"context\":{{\"intended_use\":\"intact_stability_assessment\",\"scenario_id\":\"{s}\",\"run_id\":\"box-barge-envelope-{s}\"}},\"validity\":{{\"status\":\"inside-envelope\",\"constraints\":[\"required >= 0.200 m\",\"verdict={s}\"]}},\"authority\":{{\"level\":\"unit-tested\",\"evidence_ids\":[\"imo-is-code-2008\"]}},\"operational_qualification_claimed\":false}},", .{ out.is_code.values.gz_at_30, model_ver, meta.case_id, meta.case_id, @tagName(out.is_code.gz_at_30) });

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
    try w.print("]}},\"units\":{{\"symbol\":\"m\",\"system\":\"si\"}},\"generated_at\":\"2026-07-12T01:00:00Z\",\"source\":{{\"engine\":\"yard-compose/box_barge\",\"engine_version\":\"0.0.0\",\"model\":\"wall-sided-gz\",\"model_version\":\"{s}\"}},\"context\":{{\"intended_use\":\"intact_stability_assessment\",\"scenario_id\":\"{s}\",\"run_id\":\"box-barge-envelope-{s}\"}},\"validity\":{{\"status\":\"inside-envelope\",\"constraints\":[\"wall_sided_or_small_angle\"]}},\"uncertainty\":{{\"type\":\"qualitative\",\"payload\":{{\"note\":\"box-barge analytic; not general hull offsets\"}}}},\"authority\":{{\"level\":\"unit-tested\",\"evidence_ids\":[\"yard-stability-gz\"]}},\"operational_qualification_claimed\":false}}", .{ model_ver, meta.case_id, meta.case_id });

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

test "coastal-feeder particulars produce positive volume" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input: compose.box_barge.Input = .{
        .particulars = .{ .L = 24.0, .B = 8.0, .T = 2.5 },
        .loading = .{
            .kg_m = 1.8,
            .tanks = &[_]naval.TankSpec{.{ .l_m = 8.0, .b_m = 4.0, .rho_fluid = 1000.0 }},
        },
    };
    const out = try compose.box_barge.evaluate(arena.allocator(), input);
    try std.testing.expect(out.hydrostatics.volume_m3 > 400.0);
    try std.testing.expect(out.stability.gm0_m > 0.15);
}
