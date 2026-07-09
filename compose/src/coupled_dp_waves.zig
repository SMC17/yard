//! Coupled DP station-keeping under irregular wave sway disturbance.

const std = @import("std");
const dp = @import("dp_station_keeping.zig");
const waves = @import("irregular_wave_sim.zig");
const naval = @import("yard_naval_arch");

pub const Error = error{
    SimulationFailed,
    OutOfMemory,
};

pub const Input = struct {
    length: f64,
    beam: f64,
    draft: f64,
    displacement_vol: f64,
    wetted_surface: f64,
    c_b: f64 = 0.65,
    sea: waves.SeaState,
    layout: dp.ThrusterLayout,
    kp: [3]f64 = .{ 8.0e4, 8.0e4, 3.0e6 },
    dt: f64 = 0.5,
    duration_s: f64 = 180.0,
    n_wave_components: u32 = 24,
    max_excursion_m: f64 = 6.0,
};

pub const Output = struct {
    max_excursion_m: f64,
    mean_excursion_m: f64,
    max_heave_m: f64,
    significant_heave_m: f64,
    capability_pass: bool,
    proof_level: naval.ProofLevel = .unit_tested,
};

pub fn simulate(allocator: std.mem.Allocator, input: Input) Error!Output {
    const rho: f64 = 1025.0;
    const mass = input.displacement_vol * rho;
    const d_omega = 1.2 / @as(f64, @floatFromInt(input.n_wave_components));
    const omega_min: f64 = 0.3;

    var rng = std.Random.DefaultPrng.init(0xBADA55);
    const random = rng.random();

    const fd = @import("yard_fossen").fossen;
    const p = fd.Parameters{
        .M_diag = .{ mass, mass, mass, mass * input.beam * input.beam / 12.0, mass * input.length * input.length / 12.0, mass * input.length * input.length / 12.0 },
        .D_lin = .{ 2.0e4, 2.0e4, 5.0e5, 5.0e5, 5.0e5, 5.0e5 },
        .K_z = rho * 9.80665 * input.beam * input.length,
        .K_phi = 1.0e7,
        .K_theta = 1.0e7,
    };

    const u_buf = try allocator.alloc(f64, input.layout.thrusters.len);
    defer allocator.free(u_buf);

    var state: fd.State = .{ .eta = .{ 0, 0, 0, 0, 0, 0 }, .nu = .{ 0, 0, 0, 0, 0, 0 } };
    const n_steps = @as(usize, @intFromFloat(@floor(input.duration_s / input.dt)));
    var max_exc: f64 = 0.0;
    var sum_exc: f64 = 0.0;
    var max_heave: f64 = 0.0;
    var heave_sq: f64 = 0.0;

    var step: usize = 0;
    while (step <= n_steps) : (step += 1) {
        const t = @as(f64, @floatFromInt(step)) * input.dt;
        const x = state.eta[0];
        const y = state.eta[1];
        const psi = state.eta[4];
        const exc = @sqrt(x * x + y * y);
        max_heave = @max(max_heave, @abs(state.eta[2]));
        heave_sq += state.eta[2] * state.eta[2];

        // Irregular sway disturbance from ITTC-PM components.
        var wave_sway: f64 = 0.0;
        var j: u32 = 0;
        while (j < input.n_wave_components) : (j += 1) {
            const w = omega_min + @as(f64, @floatFromInt(j)) * d_omega;
            const s = @import("yard_seakeeping").spectra.ittcModifiedPM(w, input.sea.Hs_m, input.sea.Tz_s);
            const amp = @sqrt(2.0 * s * d_omega);
            const phase = random.float(f64) * 2.0 * std.math.pi;
            wave_sway += 30_000.0 * amp * @sin(w * t + phase);
        }

        const demand: @import("yard_dynpos").allocation.Demand = .{
            .X_n = -input.kp[0] * x,
            .Y_n = -input.kp[1] * y + wave_sway,
            .N_nm = -input.kp[2] * psi,
        };

        @import("yard_dynpos").allocation.allocate(input.layout.thrusters, demand, u_buf) catch
            return Error.SimulationFailed;

        var tau: [6]f64 = .{ 0, 0, 0, 0, 0, 0 };
        for (input.layout.thrusters, 0..) |thr, i| {
            const ui = u_buf[i];
            tau[0] += @cos(thr.alpha_rad) * ui;
            tau[1] += @sin(thr.alpha_rad) * ui;
            tau[5] += (thr.x_m * @sin(thr.alpha_rad) - thr.y_m * @cos(thr.alpha_rad)) * ui;
        }

        max_exc = @max(max_exc, exc);
        sum_exc += exc;
        if (step == n_steps) break;
        state = fd.rk4Step(state, p, tau, input.dt) catch return Error.SimulationFailed;
    }

    return .{
        .max_excursion_m = max_exc,
        .mean_excursion_m = sum_exc / @as(f64, @floatFromInt(n_steps + 1)),
        .max_heave_m = max_heave,
        .significant_heave_m = @sqrt(2.0 * heave_sq / @as(f64, @floatFromInt(n_steps + 1))),
        .capability_pass = max_exc <= input.max_excursion_m,
    };
}

test "coupled DP under Hs=2 stays within generous limit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const layout = try dp.defaultLayout(arena.allocator(), 100.0, 16.0);
    const out = try simulate(arena.allocator(), .{
        .length = 100.0,
        .beam = 16.0,
        .draft = 6.0,
        .displacement_vol = 8500.0,
        .wetted_surface = 2500.0,
        .sea = .{ .Hs_m = 2.0, .Tz_s = 8.0 },
        .layout = layout,
        .duration_s = 90.0,
        .max_excursion_m = 20.0,
    });
    try std.testing.expect(out.max_excursion_m < 20.0);
}