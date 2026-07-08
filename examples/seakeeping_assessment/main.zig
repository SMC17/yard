//! Seakeeping assessment example: ITTC spectrum → strip-theory RAO → response stats + RK4 check.

const std = @import("std");
const compose = @import("yard_compose");
const hydro = @import("yard_hydro");
const naval = @import("yard_naval_arch");

pub fn main(init: std.process.Init) !u8 {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const particulars = naval.PrincipalParticulars{ .L = 100.0, .B = 16.0, .T = 6.0 };
    const barge = hydro.box_barge.Barge{
        .L = particulars.L,
        .B = particulars.B,
        .T = particulars.T,
    };
    const V = barge.volume();
    const rho: f64 = 1025.0;
    const g: f64 = 9.80665;
    const Aw = particulars.L * particulars.B;
    const C_33 = rho * g * Aw;

    const out = try compose.seakeeping_assessment.evaluate(arena.allocator(), .{
        .particulars = particulars,
        .sea = .{ .Hs_m = 2.0, .Tz_s = 8.0 },
        .heave = .{
            .M_kg = rho * V,
            .A_33 = 0.2 * rho * V,
            .B_33 = 5.0e5,
            .C_33 = C_33,
            .F_mag = C_33,
        },
        .limits = .{ .max_heave_m = 2.0, .max_roll_deg = 15.0 },
    });

    var stdout_buf: [8192]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const w = &stdout_w.interface;
    defer w.flush() catch {};

    try w.print("=== Yard: Seakeeping Assessment ===\n\n", .{});
    try w.print("Principal particulars: L={d:.0} m  B={d:.0} m  T={d:.1} m\n", .{
        particulars.L, particulars.B, particulars.T,
    });
    try w.print("Sea state: Hs={d:.1} m  Tz={d:.1} s\n\n", .{ 2.0, 8.0 });

    try w.print("--- Spectral Response ---\n", .{});
    try w.print("  Significant heave:  {d:.4} m\n", .{out.stats.significant_heave_m});
    try w.print("  Mean zero-cross T:  {d:.2} s\n", .{out.stats.mean_zero_crossing_period_s});
    try w.print("  Peak RAO:           {d:.4} m/m @ ω={d:.2} rad/s\n", .{
        out.stats.peak_rao, out.stats.peak_omega_rad_s,
    });
    try w.print("  m₀ (response):      {d:.6}\n\n", .{out.stats.m0_response});

    try w.print("--- RK4 Simulation (harmonic @ peak ω) ---\n", .{});
    try w.print("  Max heave:          {d:.4} m\n", .{out.simulation.max_heave_m});
    try w.print("  Max roll:           {d:.2}°\n", .{naval.units.radToDeg(out.simulation.max_roll_rad)});
    try w.print("  Operability:        {}\n\n", .{out.simulation.operability_pass});

    try w.print("--- Validity Flags ---\n", .{});
    if (out.flags.contains(.small_angle_regime))
        try w.print("  ✓ small_angle_regime\n", .{});
    if (out.flags.contains(.wall_sided_assumption_valid))
        try w.print("  ✓ wall_sided_assumption_valid\n", .{});
    if (out.flags.contains(.outside_validity_envelope))
        try w.print("  ⚠ outside_validity_envelope\n", .{});

    try w.print("\nProof level: unit-tested (not operational seakeeping grade)\n", .{});
    return 0;
}

test "seakeeping example compiles and runs workflow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const out = try compose.seakeeping_assessment.evaluate(arena.allocator(), .{
        .particulars = .{ .L = 100.0, .B = 16.0, .T = 6.0 },
        .sea = .{ .Hs_m = 2.0, .Tz_s = 8.0 },
        .heave = .{
            .M_kg = 1.0e6,
            .A_33 = 2.0e5,
            .B_33 = 5.0e5,
            .C_33 = 1.0e7,
            .F_mag = 1.0e7,
        },
    });
    try std.testing.expect(out.stats.significant_heave_m > 0.0);
}