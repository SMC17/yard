//! Evans Spiral demo: Wigley hull model test → full-scale ITTC-78 extrapolation.
//!
//! Demonstrates the three similarity rules:
//!   geometric  — λ = L_model / L_ship
//!   kinematic  — Froude-matched speeds
//!   dynamic    — separate C_F at model and ship Reynolds numbers

const std = @import("std");
const hydro = @import("yard_hydro");
const similarity = @import("yard_similarity");
const compose = @import("yard_compose");
const spiral = @import("yard_spiral");
const naval = @import("yard_naval_arch");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;

    var stdout_buf: [8192]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_w.interface;
    defer stdout.flush() catch {};

    // Full-scale Wigley target (Kajitani-Miyata canonical proportions).
    const l_ship: f64 = 100.0;
    const b_ship: f64 = 10.0;
    const t_ship: f64 = 6.25;
    const l_model: f64 = 5.0;
    const service_speed: f64 = 8.0;
    const g: f64 = naval.PhysicalConstants.default.g;
    const nu: f64 = naval.PhysicalConstants.default.nu;

    const wigley_ship = hydro.wigley.Hull{ .L = l_ship, .B = b_ship, .T = t_ship };
    const vol = wigley_ship.volume();
    const disp = vol * naval.PhysicalConstants.default.rho_seawater;

    try stdout.print("=== Yard Evans Design Spiral — Wigley Model Test Demo ===\n\n", .{});
    try stdout.print("Full-scale Wigley: L={d:.1} B={d:.1} T={d:.1} C_B={d:.4}\n", .{
        l_ship, b_ship, t_ship, wigley_ship.cB(),
    });
    try stdout.print("Displacement: {d:.0} t\n\n", .{disp / 1000.0});

    // Three rules check.
    const sr = try similarity.scale.ScaleRatio.fromLengths(l_model, l_ship);
    const v_model = try sr.modelSpeedFromShip(service_speed, g);
    const rules = try similarity.scale.evaluateThreeRules(l_model, l_ship, v_model, service_speed, nu, g, 0.01, 0.05);

    try stdout.print("--- Similarity (three rules) ---\n", .{});
    try stdout.print("λ = {d:.4}\n", .{rules.lambda});
    try stdout.print("Model speed (Froude-matched): {d:.3} m/s\n", .{v_model});
    try stdout.print("Fn model={d:.4} ship={d:.4}  kinematic_ok={}\n", .{ rules.fn_model, rules.fn_ship, rules.kinematic_ok });
    const expected_rn = 1.0 / (rules.lambda * @sqrt(rules.lambda));
    try stdout.print("Rn ratio (ship/model) = {d:.2}  (expected λ^(-3/2) = {d:.2})\n\n", .{
        rules.reynolds_ratio, expected_rn,
    });

    // High-fidelity spiral with model test path.
    var orch = spiral.orchestrator.Orchestrator.init(allocator, 2, .high);
    var spiral_out = try orch.runSpiral(.{
        .length = l_ship,
        .beam = b_ship,
        .draft = t_ship,
        .displacement = disp,
        .kg = wigley_ship.kb() + 2.0,
        .service_speed = service_speed,
        .c_b = wigley_ship.cB(),
        .model_length = l_model,
    });
    defer orch.freeSpiralResult(&spiral_out);

    try stdout.print("--- Evans Spiral (high fidelity, 2 loops) ---\n", .{});
    try stdout.print("Loops: {d}  converged: {}\n", .{ spiral_out.loops, spiral_out.converged });
    try stdout.print("GM = {d:.3} m\n", .{spiral_out.final.gm_m});
    try stdout.print("P_E ≈ {d:.0} kW\n", .{spiral_out.final.estimated_power_kw});
    try stdout.print("Objective score = {d:.4}\n\n", .{
        spiral.orchestrator.evaluateObjective(spiral_out.final, 0.5),
    });

    // GA + code generation pass.
    const optimized = try spiral.optimizer.gaHullOptimize(orch, 10, 3, 0.5);
    const code = try spiral.codegen.generateNavalCode(allocator, optimized, "WigleyOptimized");
    defer allocator.free(code);

    try stdout.print("--- GA optimize + naval compile ---\n", .{});
    try stdout.print("Optimized L={d:.1} B={d:.1} T={d:.1} P_E≈{d:.0} kW\n", .{
        optimized.length, optimized.beam, optimized.draft, optimized.estimated_power_kw,
    });
    try stdout.print("Generated {d} bytes of Zig simulator skeleton\n\n", .{code.len});

    // Time-domain sim snippet.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const sim = try compose.time_domain_sim.simulate(arena.allocator(), .{
        .length = l_ship,
        .beam = b_ship,
        .draft = t_ship,
        .displacement_vol = vol,
        .wetted_surface = 2.6 * @sqrt(vol) * l_ship,
        .c_b = wigley_ship.cB(),
        .u0 = 2.0,
        .thrust_n = 400_000.0,
        .dt = 0.5,
        .n_steps = 40,
    });

    try stdout.print("--- Time-domain 6-DOF (surge) ---\n", .{});
    try stdout.print("u₀=2.0 m/s  thrust=400 kN  steps=40\n", .{});
    try stdout.print("u_final={d:.3} m/s  R_drag={d:.0} N\n", .{ sim.final_u, sim.r_drag_final });
    return 0;
}

test "demo constants are self-consistent" {
    const wigley = hydro.wigley.Hull{ .L = 100.0, .B = 10.0, .T = 6.25 };
    try std.testing.expectApproxEqAbs(@as(f64, 4.0 / 9.0), wigley.cB(), 1e-12);
}