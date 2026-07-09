//! Minimal time-domain 6-DOF simulator composing fossen-6dof + resistance drag.
//!
//! Proof level: unit-tested. Linear Fossen RK4 with quasi-steady resistance
//! thrust opposing surge motion.

const std = @import("std");
const fossen = @import("yard_fossen");
const resistance = @import("yard_resistance");
const naval = @import("yard_naval_arch");

pub const Error = error{
    SimulationFailed,
    OutsideValidityEnvelope,
    OutOfMemory,
};

pub const Environment = struct {
    rho: f64 = 1025.0,
    nu: f64 = 1.188e-6,
    g: f64 = 9.80665,
};

pub const Input = struct {
    /// Principal particulars for resistance.
    length: f64,
    beam: f64,
    draft: f64,
    displacement_vol: f64,
    wetted_surface: f64,
    c_b: f64 = 0.65,
    /// Initial surge speed [m/s].
    u0: f64 = 0.0,
    /// Propeller thrust in surge [N] (body x).
    thrust_n: f64 = 0.0,
    /// Timestep [s].
    dt: f64 = 0.1,
    /// Number of steps.
    n_steps: u32 = 100,
    env: Environment = .{},
};

pub const StateSample = struct {
    t: f64,
    u: f64,
    x: f64,
};

pub const Output = struct {
    samples: []StateSample,
    final_u: f64,
    r_drag_final: f64,
    proof_level: naval.ProofLevel = .unit_tested,
};

pub fn simulate(allocator: std.mem.Allocator, input: Input) Error!Output {
    const hp = resistance.holtrop.HullParticulars{
        .L = input.length,
        .B = input.beam,
        .T = input.draft,
        .displacement_vol = input.displacement_vol,
        .S = input.wetted_surface,
        .C_B = input.c_b,
        .C_M = 0.98,
        .C_P = 0.66,
        .C_WP = 0.78,
        .lcb_pct = 0.0,
        .c_stern = 0.0,
    };

    const fd = fossen.fossen;
    const p = fd.Parameters{
        .M_diag = .{ input.displacement_vol * input.env.rho, 1.0e6, 1.0e6, 1.0e7, 1.0e7, 1.0e7 },
        .D_lin = .{ 1.0e4, 1.0e4, 1.0e4, 1.0e5, 1.0e5, 1.0e5 },
        .K_z = 1.0e6,
        .K_phi = 1.0e7,
        .K_theta = 1.0e7,
    };

    var samples = try allocator.alloc(StateSample, input.n_steps + 1);
    errdefer allocator.free(samples);

    var state: fd.State = .{
        .eta = .{ 0, 0, 0, 0, 0, 0 },
        .nu = .{ input.u0, 0, 0, 0, 0, 0 },
    };

    var r_drag: f64 = 0.0;
    var step: u32 = 0;
    while (step <= input.n_steps) : (step += 1) {
        const t = @as(f64, @floatFromInt(step)) * input.dt;
        const u = state.nu[0];
        const bd = resistance.holtrop.totalResistance(hp, @max(u, 0.01), .{
            .rho = input.env.rho,
            .nu = input.env.nu,
            .g = input.env.g,
        }) catch return Error.SimulationFailed;
        r_drag = bd.r_total;
        const tau: [6]f64 = .{ input.thrust_n - r_drag, 0, 0, 0, 0, 0 };
        samples[step] = .{ .t = t, .u = u, .x = state.eta[0] };
        if (step == input.n_steps) break;
        state = fd.rk4Step(state, p, tau, input.dt) catch return Error.SimulationFailed;
    }

    return .{
        .samples = samples,
        .final_u = state.nu[0],
        .r_drag_final = r_drag,
    };
}

test "acceleration under thrust exceeds coast-down" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const thrust_run = try simulate(arena.allocator(), .{
        .length = 100.0,
        .beam = 16.0,
        .draft = 6.0,
        .displacement_vol = 8500.0,
        .wetted_surface = 2500.0,
        .u0 = 2.0,
        .thrust_n = 500_000.0,
        .dt = 0.5,
        .n_steps = 20,
    });
    const coast_run = try simulate(arena.allocator(), .{
        .length = 100.0,
        .beam = 16.0,
        .draft = 6.0,
        .displacement_vol = 8500.0,
        .wetted_surface = 2500.0,
        .u0 = 2.0,
        .thrust_n = 0.0,
        .dt = 0.5,
        .n_steps = 20,
    });
    try std.testing.expect(thrust_run.final_u > coast_run.final_u);
}