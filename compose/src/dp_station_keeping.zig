//! Dynamic positioning station-keeping under wave disturbance.
//! Wires dynpos/allocation + fossen-6dof RK4 with proportional position hold.

const std = @import("std");
const dynpos = @import("yard_dynpos");
const fossen = @import("yard_fossen");
const naval = @import("yard_naval_arch");

pub const Error = error{
    AllocationFailed,
    SimulationFailed,
    OutOfMemory,
};

pub const ThrusterLayout = struct {
    thrusters: []const dynpos.allocation.Thruster,
};

/// Default 3-thruster DP layout for a vessel of given length/beam.
pub fn defaultLayout(allocator: std.mem.Allocator, length: f64, beam: f64) !ThrusterLayout {
    const thr = try allocator.alloc(dynpos.allocation.Thruster, 3);
    thr[0] = .{ .alpha_rad = std.math.pi / 2.0, .x_m = length / 2.0, .y_m = 0.0 };
    thr[1] = .{ .alpha_rad = 0.0, .x_m = -length / 2.0, .y_m = beam / 2.0 };
    thr[2] = .{ .alpha_rad = 0.0, .x_m = -length / 2.0, .y_m = -beam / 2.0 };
    return .{ .thrusters = thr };
}

pub const Input = struct {
    mass_kg: f64,
    length: f64,
    beam: f64,
    layout: ThrusterLayout,
    /// Proportional gains [surge, sway, yaw] on position error.
    kp: [3]f64 = .{ 5.0e4, 5.0e4, 2.0e6 },
    /// Wave disturbance amplitude in sway [N].
    wave_sway_amp_n: f64 = 50_000.0,
    wave_omega_rad_s: f64 = 0.8,
    dt: f64 = 0.5,
    duration_s: f64 = 120.0,
    /// Max allowed horizontal excursion [m] for capability pass.
    max_excursion_m: f64 = 5.0,
};

pub const Sample = struct {
    t: f64,
    x: f64,
    y: f64,
    psi_rad: f64,
    excursion_m: f64,
};

pub const Output = struct {
    samples: []Sample,
    max_excursion_m: f64,
    mean_excursion_m: f64,
    closing_residual_max: f64,
    capability_pass: bool,
    proof_level: naval.ProofLevel = .unit_tested,
};

pub fn simulate(allocator: std.mem.Allocator, input: Input) Error!Output {
    const fd = fossen.fossen;
    const p = fd.Parameters{
        .M_diag = .{ input.mass_kg, input.mass_kg, input.mass_kg, input.mass_kg * input.beam * input.beam / 12.0, input.mass_kg * input.length * input.length / 12.0, input.mass_kg * input.length * input.length / 12.0 },
        .D_lin = .{ 2.0e4, 2.0e4, 1.0e4, 5.0e5, 5.0e5, 5.0e5 },
        .K_z = 1.0e6,
        .K_phi = 1.0e7,
        .K_theta = 1.0e7,
    };

    const n_steps = @as(usize, @intFromFloat(@floor(input.duration_s / input.dt)));
    var samples = try allocator.alloc(Sample, n_steps + 1);
    errdefer allocator.free(samples);

    const u_buf = try allocator.alloc(f64, input.layout.thrusters.len);
    defer allocator.free(u_buf);

    var state: fd.State = .{ .eta = .{ 0, 0, 0, 0, 0, 0 }, .nu = .{ 0, 0, 0, 0, 0, 0 } };
    var max_exc: f64 = 0.0;
    var sum_exc: f64 = 0.0;
    var max_residual: f64 = 0.0;
    var step: usize = 0;

    while (step <= n_steps) : (step += 1) {
        const t = @as(f64, @floatFromInt(step)) * input.dt;
        const x = state.eta[0];
        const y = state.eta[1];
        const psi = state.eta[4];
        const exc = @sqrt(x * x + y * y);

        const demand: dynpos.allocation.Demand = .{
            .X_n = -input.kp[0] * x,
            .Y_n = -input.kp[1] * y + input.wave_sway_amp_n * @sin(input.wave_omega_rad_s * t),
            .N_nm = -input.kp[2] * psi,
        };

        dynpos.allocation.allocate(input.layout.thrusters, demand, u_buf) catch return Error.AllocationFailed;
        const residual = dynpos.allocation.closingResidual(input.layout.thrusters, u_buf, demand) catch return Error.AllocationFailed;
        max_residual = @max(max_residual, residual);

        var tau: [6]f64 = .{ 0, 0, 0, 0, 0, 0 };
        for (input.layout.thrusters, 0..) |thr, i| {
            const ui = u_buf[i];
            tau[0] += @cos(thr.alpha_rad) * ui;
            tau[1] += @sin(thr.alpha_rad) * ui;
            tau[5] += (thr.x_m * @sin(thr.alpha_rad) - thr.y_m * @cos(thr.alpha_rad)) * ui;
        }

        samples[step] = .{ .t = t, .x = x, .y = y, .psi_rad = psi, .excursion_m = exc };
        max_exc = @max(max_exc, exc);
        sum_exc += exc;

        if (step == n_steps) break;
        state = fd.rk4Step(state, p, tau, input.dt) catch return Error.SimulationFailed;
    }

    const mean_exc = sum_exc / @as(f64, @floatFromInt(n_steps + 1));
    return .{
        .samples = samples,
        .max_excursion_m = max_exc,
        .mean_excursion_m = mean_exc,
        .closing_residual_max = max_residual,
        .capability_pass = max_exc <= input.max_excursion_m,
    };
}

test "DP holds position within excursion limit in mild waves" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const layout = try defaultLayout(arena.allocator(), 100.0, 16.0);
    const out = try simulate(arena.allocator(), .{
        .mass_kg = 8.7e6,
        .length = 100.0,
        .beam = 16.0,
        .layout = layout,
        .wave_sway_amp_n = 20_000.0,
        .duration_s = 60.0,
        .max_excursion_m = 15.0,
    });
    try std.testing.expect(out.max_excursion_m < 15.0);
    try std.testing.expect(out.closing_residual_max < 100.0);
}