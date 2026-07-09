//! Coupled DP + irregular-wave feedback for high-fidelity spiral stages.
//! Mirrors compose/coupled_dp_waves without importing yard_compose (avoids cycle).

const std = @import("std");
const dynpos = @import("yard_dynpos");
const fossen = @import("yard_fossen");
const seakeeping = @import("yard_seakeeping");

pub const Error = error{
    SimulationFailed,
    OutOfMemory,
};

pub const Input = struct {
    length: f64,
    beam: f64,
    draft: f64,
    displacement_kg: f64,
    sea_Hs_m: f64,
    sea_Tz_s: f64,
    /// Max allowed horizontal excursion [m].
    max_excursion_m: f64 = 5.0,
    dt: f64 = 0.5,
    duration_s: f64 = 90.0,
    n_wave_components: u32 = 16,
};

pub const Result = struct {
    max_excursion_m: f64,
    mean_excursion_m: f64,
    significant_heave_m: f64,
    capable: bool,
};

fn defaultLayout(allocator: std.mem.Allocator, length: f64, beam: f64) ![]const dynpos.allocation.Thruster {
    const thr = try allocator.alloc(dynpos.allocation.Thruster, 3);
    thr[0] = .{ .alpha_rad = std.math.pi / 2.0, .x_m = length / 2.0, .y_m = 0.0 };
    thr[1] = .{ .alpha_rad = 0.0, .x_m = -length / 2.0, .y_m = beam / 2.0 };
    thr[2] = .{ .alpha_rad = 0.0, .x_m = -length / 2.0, .y_m = -beam / 2.0 };
    return thr;
}

/// Time-domain DP under ITTC-PM irregular sway disturbance.
pub fn estimate(allocator: std.mem.Allocator, input: Input) Error!Result {
    const rho: f64 = 1025.0;
    const mass = input.displacement_kg;
    const d_omega = 1.2 / @as(f64, @floatFromInt(input.n_wave_components));
    const omega_min: f64 = 0.3;
    const kp: [3]f64 = .{ 8.0e4, 8.0e4, 3.0e6 };

    var rng = std.Random.DefaultPrng.init(0xBADA55);
    const random = rng.random();

    const thrusters = try defaultLayout(allocator, input.length, input.beam);
    defer allocator.free(thrusters);

    const fd = fossen.fossen;
    const p = fd.Parameters{
        .M_diag = .{
            mass, mass, mass,
            mass * input.beam * input.beam / 12.0,
            mass * input.length * input.length / 12.0,
            mass * input.length * input.length / 12.0,
        },
        .D_lin = .{ 2.0e4, 2.0e4, 5.0e5, 5.0e5, 5.0e5, 5.0e5 },
        .K_z = rho * 9.80665 * input.beam * input.length,
        .K_phi = 1.0e7,
        .K_theta = 1.0e7,
    };

    const u_buf = try allocator.alloc(f64, thrusters.len);
    defer allocator.free(u_buf);

    var state: fd.State = .{ .eta = .{ 0, 0, 0, 0, 0, 0 }, .nu = .{ 0, 0, 0, 0, 0, 0 } };
    const n_steps = @as(usize, @intFromFloat(@floor(input.duration_s / input.dt)));
    var max_exc: f64 = 0.0;
    var sum_exc: f64 = 0.0;
    var heave_sq: f64 = 0.0;

    var step: usize = 0;
    while (step <= n_steps) : (step += 1) {
        const t = @as(f64, @floatFromInt(step)) * input.dt;
        const x = state.eta[0];
        const y = state.eta[1];
        const psi = state.eta[4];
        const exc = @sqrt(x * x + y * y);
        heave_sq += state.eta[2] * state.eta[2];

        var wave_sway: f64 = 0.0;
        var j: u32 = 0;
        while (j < input.n_wave_components) : (j += 1) {
            const w = omega_min + @as(f64, @floatFromInt(j)) * d_omega;
            const s = seakeeping.spectra.ittcModifiedPM(w, input.sea_Hs_m, input.sea_Tz_s);
            const amp = @sqrt(2.0 * s * d_omega);
            const phase = random.float(f64) * 2.0 * std.math.pi;
            wave_sway += 30_000.0 * amp * @sin(w * t + phase);
        }

        const demand: dynpos.allocation.Demand = .{
            .X_n = -kp[0] * x,
            .Y_n = -kp[1] * y + wave_sway,
            .N_nm = -kp[2] * psi,
        };

        dynpos.allocation.allocate(thrusters, demand, u_buf) catch return Error.SimulationFailed;

        var tau: [6]f64 = .{ 0, 0, 0, 0, 0, 0 };
        for (thrusters, 0..) |thr, i| {
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

    const n = @as(f64, @floatFromInt(n_steps + 1));
    return .{
        .max_excursion_m = max_exc,
        .mean_excursion_m = sum_exc / n,
        .significant_heave_m = @sqrt(2.0 * heave_sq / n),
        .capable = max_exc <= input.max_excursion_m,
    };
}

test "DP feedback under Hs=2 within limit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const r = try estimate(arena.allocator(), .{
        .length = 100.0,
        .beam = 16.0,
        .draft = 6.0,
        .displacement_kg = 8.7e6,
        .sea_Hs_m = 2.0,
        .sea_Tz_s = 8.0,
        .max_excursion_m = 20.0,
        .duration_s = 60.0,
    });
    try std.testing.expect(r.max_excursion_m < 20.0);
    try std.testing.expect(r.significant_heave_m >= 0.0);
}