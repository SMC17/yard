//! Combined demo: DP station-keeping + irregular waves + Pareto SVG export.

const std = @import("std");
const compose = @import("yard_compose");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;

    var stdout_buf: [8192]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const w = &stdout_w.interface;
    defer w.flush() catch {};

    try w.print("=== Yard Sim Suite Demo ===\n\n", .{});

    // DP station-keeping
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const layout = try compose.dp_station_keeping.defaultLayout(arena.allocator(), 100.0, 16.0);
    const dp = try compose.dp_station_keeping.simulate(arena.allocator(), .{
        .mass_kg = 8.7e6,
        .length = 100.0,
        .beam = 16.0,
        .layout = layout,
        .wave_sway_amp_n = 30_000.0,
        .duration_s = 90.0,
        .max_excursion_m = 8.0,
    });
    try w.print("--- DP Station-Keeping ---\n", .{});
    try w.print("max excursion = {d:.3} m  mean = {d:.3} m  pass = {}\n\n", .{
        dp.max_excursion_m, dp.mean_excursion_m, dp.capability_pass,
    });

    // Irregular waves
    const waves = try compose.irregular_wave_sim.simulate(arena.allocator(), .{
        .length = 100.0,
        .beam = 16.0,
        .draft = 6.0,
        .displacement_vol = 8500.0,
        .wetted_surface = 2500.0,
        .sea = .{ .Hs_m = 2.0, .Tz_s = 8.0 },
        .duration_s = 120.0,
        .n_components = 24,
    });
    try w.print("--- Irregular Waves (time-domain) ---\n", .{});
    try w.print("max heave = {d:.3} m  sig heave = {d:.3} m\n\n", .{
        waves.max_heave_m, waves.significant_heave_m,
    });

    // Pareto campaign + SVG
    var campaign = try compose.pareto_report.runCampaign(arena.allocator(), 6, 2, 0.5);
    defer campaign.deinit(arena.allocator());
    try w.print("--- Pareto Campaign ---\n", .{});
    try w.print("front size = {d}  svg bytes = {d}\n", .{ campaign.front.len, campaign.svg.len });

    try w.print("Pareto SVG preview (first 80 chars): {s}...\n", .{campaign.svg[0..@min(80, campaign.svg.len)]});
    return 0;
}

test "demo modules link" {
    _ = compose.dp_station_keeping;
    _ = compose.irregular_wave_sim;
    _ = compose.pareto_report;
}