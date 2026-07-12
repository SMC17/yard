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
const viz = @import("yard_viz");

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
    try stdout.print("Sig heave (operability) = {d:.3} m\n", .{spiral_out.final.significant_heave_m});
    try stdout.print("DP max excursion = {d:.3} m  capable = {}\n", .{
        spiral_out.final.dp_max_excursion_m, spiral_out.final.dp_capable,
    });
    try stdout.print("Objective score = {d:.4}\n\n", .{
        spiral.orchestrator.evaluateObjective(spiral_out.final, 0.5),
    });

    // 1. Pareto exploration campaign
    const pareto_pts = try spiral.optimizer.gaParetoExplore(orch, 8, 3, 0.5);
    defer allocator.free(pareto_pts);

    // 2. Generate Pareto Front SVG
    const viz_points = try allocator.alloc(viz.pareto_svg.Point, pareto_pts.len);
    defer allocator.free(viz_points);
    for (pareto_pts, 0..) |p, idx| {
        viz_points[idx] = .{
            .power_kw = p.power_kw,
            .heave_m = p.heave_m,
            .gm_m = p.gm_m,
        };
    }
    const front_indices = try allocator.alloc(usize, pareto_pts.len);
    defer allocator.free(front_indices);
    for (front_indices, 0..) |*i, idx| i.* = idx;

    var svg_buf: std.ArrayList(u8) = .empty;
    defer svg_buf.deinit(allocator);
    try viz.pareto_svg.render(&svg_buf, allocator, .{
        .points = viz_points,
        .front_indices = front_indices,
    });

    // Write SVG to file
    var svg_file = try std.Io.Dir.cwd().createFile(init.io, "examples/design-spiral-wigley/pareto_front.svg", .{});
    defer svg_file.close(init.io);
    var svg_write_buf: [4096]u8 = undefined;
    var svg_writer = svg_file.writer(init.io, &svg_write_buf);
    try svg_writer.interface.writeAll(svg_buf.items);
    try svg_writer.interface.flush();

    // 3. Multi-objective GA optimization
    const optimized = try spiral.optimizer.gaHullOptimize(orch, 12, 4, 0.5);

    // 4. Multi-variable Gradient Descent Fine-tuning (Length, Beam, Draft)
    const fine_tuned = try spiral.optimizer.gradientOptimizeMulti(orch, optimized, 1.0, 0.2, 0.1, 0.05, 5, 0.5);

    // 5. Code compilation generation (naval compiler output)
    const code = try spiral.codegen.generateNavalCode(allocator, fine_tuned, "WigleyOptimized");
    defer allocator.free(code);

    // Write generated Zig simulation code to file
    var code_file = try std.Io.Dir.cwd().createFile(init.io, "examples/design-spiral-wigley/vessel_sim.zig", .{});
    defer code_file.close(init.io);
    var code_write_buf: [4096]u8 = undefined;
    var code_writer = code_file.writer(init.io, &code_write_buf);
    try code_writer.interface.writeAll(code);
    try code_writer.interface.flush();

    try stdout.print("--- GA + Gradient Optimize & Naval Compiler Output ---\n", .{});
    try stdout.print("Initial seed:  L=100.0, B=10.0, T=6.25\n", .{});
    try stdout.print("GA Optimized:  L={d:.1} B={d:.1} T={d:.1} P_E≈{d:.0} kW\n", .{
        optimized.length, optimized.beam, optimized.draft, optimized.estimated_power_kw,
    });
    try stdout.print("Fine-tuned:    L={d:.1} B={d:.1} T={d:.1} P_E≈{d:.0} kW\n", .{
        fine_tuned.length, fine_tuned.beam, fine_tuned.draft, fine_tuned.estimated_power_kw,
    });
    try stdout.print("Wrote Pareto Front SVG to examples/design-spiral-wigley/pareto_front.svg ({d} bytes)\n", .{svg_buf.items.len});
    try stdout.print("Wrote generated simulator to examples/design-spiral-wigley/vessel_sim.zig ({d} bytes)\n\n", .{code.len});

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