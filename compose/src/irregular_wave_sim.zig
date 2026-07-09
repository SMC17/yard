//! Irregular-wave time-domain simulator: ITTC-PM spectrum → multi-sine forcing.
//!
//! Composes seakeeping/spectra + fossen-6dof RK4 + optional Holtrop surge drag.

const std = @import("std");
const fossen = @import("yard_fossen");
const seakeeping = @import("yard_seakeeping");
const resistance = @import("yard_resistance");
const naval = @import("yard_naval_arch");

pub const Error = error{
    InvalidSeaState,
    SimulationFailed,
    OutOfMemory,
};

pub const SeaState = struct {
    Hs_m: f64,
    Tz_s: f64,
};

pub const Input = struct {
    length: f64,
    beam: f64,
    draft: f64,
    displacement_vol: f64,
    wetted_surface: f64,
    c_b: f64 = 0.65,
    sea: SeaState,
    /// Number of frequency components for irregular synthesis.
    n_components: u32 = 32,
    omega_min: f64 = 0.3,
    omega_max: f64 = 1.5,
    /// Heave excitation scale (Froude-Krylov proxy).
    force_scale: f64 = 1.0,
    u0: f64 = 0.0,
    thrust_n: f64 = 0.0,
    dt: f64 = 0.25,
    duration_s: f64 = 300.0,
    /// Deterministic phase seed for reproducible tests.
    phase_seed: u64 = 0xC0FFEE,
    env: struct {
        rho: f64 = 1025.0,
        nu: f64 = 1.188e-6,
        g: f64 = 9.80665,
    } = .{},
};

pub const TimeSample = struct {
    t: f64,
    heave_m: f64,
    surge_u: f64,
    wave_eta_m: f64,
};

pub const Output = struct {
    samples: []TimeSample,
    max_heave_m: f64,
    significant_heave_m: f64,
    max_wave_eta_m: f64,
    final_surge_u: f64,
    proof_level: naval.ProofLevel = .unit_tested,
};

pub fn simulate(allocator: std.mem.Allocator, input: Input) Error!Output {
    if (input.sea.Hs_m <= 0.0 or input.sea.Tz_s <= 0.0 or input.n_components == 0)
        return Error.InvalidSeaState;

    const n_comp = input.n_components;
    const d_omega = (input.omega_max - input.omega_min) / @as(f64, @floatFromInt(n_comp -| 1));

    var omegas = try allocator.alloc(f64, n_comp);
    defer allocator.free(omegas);
    var amplitudes = try allocator.alloc(f64, n_comp);
    defer allocator.free(amplitudes);
    var phases = try allocator.alloc(f64, n_comp);
    defer allocator.free(phases);

    var rng = std.Random.DefaultPrng.init(input.phase_seed);
    const random = rng.random();

    var i: u32 = 0;
    while (i < n_comp) : (i += 1) {
        const w = input.omega_min + @as(f64, @floatFromInt(i)) * d_omega;
        omegas[i] = w;
        const s = seakeeping.spectra.ittcModifiedPM(w, input.sea.Hs_m, input.sea.Tz_s);
        amplitudes[i] = @sqrt(2.0 * s * d_omega);
        phases[i] = random.float(f64) * 2.0 * std.math.pi;
    }

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

    const rho = input.env.rho;
    const g = input.env.g;
    const Aw = input.beam * input.length;
    const K_z = rho * g * Aw * input.force_scale;
    const mass = input.displacement_vol * rho;

    const fd = fossen.fossen;
    const p = fd.Parameters{
        .M_diag = .{ mass, mass, mass, mass * input.beam * input.beam / 12.0, mass * input.length * input.length / 12.0, mass * input.length * input.length / 12.0 },
        .D_lin = .{ 1.0e4, 1.0e4, 5.0e5, 1.0e5, 1.0e5, 1.0e5 },
        .K_z = K_z,
        .K_phi = 1.0e7,
        .K_theta = 1.0e7,
    };

    const n_steps = @as(usize, @intFromFloat(@floor(input.duration_s / input.dt)));
    var samples = try allocator.alloc(TimeSample, n_steps + 1);
    errdefer allocator.free(samples);

    var state: fd.State = .{
        .eta = .{ 0, 0, 0, 0, 0, 0 },
        .nu = .{ input.u0, 0, 0, 0, 0, 0 },
    };

    var max_heave: f64 = 0.0;
    var max_wave: f64 = 0.0;
    var heave_sq_sum: f64 = 0.0;
    var step: usize = 0;
    while (step <= n_steps) : (step += 1) {
        const t = @as(f64, @floatFromInt(step)) * input.dt;

        var wave_eta: f64 = 0.0;
        var force_z: f64 = 0.0;
        var j: u32 = 0;
        while (j < n_comp) : (j += 1) {
            const phase = omegas[j] * t + phases[j];
            wave_eta += amplitudes[j] * @cos(phase);
            force_z += K_z * amplitudes[j] * @sin(phase);
        }

        const u = state.nu[0];
        const bd = resistance.holtrop.totalResistance(hp, @max(u, 0.01), .{
            .rho = rho,
            .nu = input.env.nu,
            .g = g,
        }) catch return Error.SimulationFailed;

        const tau: [6]f64 = .{ input.thrust_n - bd.r_total, 0, force_z, 0, 0, 0 };
        samples[step] = .{
            .t = t,
            .heave_m = state.eta[2],
            .surge_u = u,
            .wave_eta_m = wave_eta,
        };

        max_heave = @max(max_heave, @abs(state.eta[2]));
        max_wave = @max(max_wave, @abs(wave_eta));
        heave_sq_sum += state.eta[2] * state.eta[2];

        if (step == n_steps) break;
        state = fd.rk4Step(state, p, tau, input.dt) catch return Error.SimulationFailed;
    }

    const sig_heave = @sqrt(2.0 * heave_sq_sum / @as(f64, @floatFromInt(n_steps + 1)));

    return .{
        .samples = samples,
        .max_heave_m = max_heave,
        .significant_heave_m = sig_heave,
        .max_wave_eta_m = max_wave,
        .final_surge_u = state.nu[0],
    };
}

test "irregular wave sim produces motion under Hs=2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const out = try simulate(arena.allocator(), .{
        .length = 100.0,
        .beam = 16.0,
        .draft = 6.0,
        .displacement_vol = 8500.0,
        .wetted_surface = 2500.0,
        .sea = .{ .Hs_m = 2.0, .Tz_s = 8.0 },
        .n_components = 16,
        .duration_s = 60.0,
        .dt = 0.5,
    });
    try std.testing.expect(out.max_heave_m > 0.0);
    try std.testing.expect(out.significant_heave_m > 0.0);
    try std.testing.expect(out.max_wave_eta_m > 0.0);
}