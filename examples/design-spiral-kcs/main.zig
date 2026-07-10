//! Evans Spiral demo: KCS benchmark hull with published tank C_T ingest.

const std = @import("std");
const benchmark = @import("yard_benchmark");
const spiral = @import("yard_spiral");
const naval = @import("yard_naval_arch");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;

    var stdout_buf: [8192]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const w = &stdout_w.interface;
    defer w.flush() catch {};

    const f = benchmark.hulls.get(.kcs);
    const rho = naval.PhysicalConstants.default.rho_seawater;

    try w.print("=== Yard Evans Spiral — KCS Tank Ingest Demo ===\n\n", .{});
    try w.print("KCS: L={d:.1} B={d:.1} T={d:.1} C_B={d:.4}\n", .{ f.L, f.B, f.T, f.C_B });
    try w.print("Service speed: {d:.2} m/s  model L: {d:.1} m\n\n", .{ f.service_speed, f.modelLength() });

    var orch = spiral.orchestrator.Orchestrator.init(allocator, 2, .high);
    var result = try orch.runSpiral(.{
        .length = f.L,
        .beam = f.B,
        .draft = f.T,
        .displacement = f.displacement_vol * rho,
        .service_speed = f.service_speed,
        .c_b = f.C_B,
        .tank_hull = .kcs,
        .sea_Hs_m = 2.0,
        .sea_Tz_s = 8.0,
    });
    defer orch.freeSpiralResult(&result);

    try w.print("--- Evans Spiral (tank C_T path) ---\n", .{});
    try w.print("Loops: {d}  converged: {}\n", .{ result.loops, result.converged });
    try w.print("P_E ≈ {d:.0} kW\n", .{result.final.estimated_power_kw});
    try w.print("Sig heave = {d:.3} m  DP excursion = {d:.3} m  capable = {}\n", .{
        result.final.significant_heave_m,
        result.final.dp_max_excursion_m,
        result.final.dp_capable,
    });

    try w.print("Objective score = {d:.4}\n", .{
        spiral.orchestrator.evaluateObjective(result.final, 0.5),
    });
    return 0;
}

test "KCS spiral demo links" {
    _ = benchmark.hulls;
    _ = spiral.orchestrator.TankHull;
}