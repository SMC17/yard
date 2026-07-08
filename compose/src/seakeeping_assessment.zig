//! Seakeeping assessment: wave spectrum → strip-theory heave RAO → response stats.
//! Wires seakeeping/spectra + strip-theory/heave + rao-spectrum + fossen-6dof (RK4).

const std = @import("std");
const hydro = @import("yard_hydro");
const naval = @import("yard_naval_arch");
const seakeeping = @import("yard_seakeeping");
const rao = @import("yard_rao_spectrum");
const strip = @import("yard_strip_theory");
const fossen = @import("yard_fossen");

pub const Error = error{
    InvalidSeaState,
    SpectrumIntegrationFailed,
    RAOComputationFailed,
    SimulationFailed,
    OutOfMemory,
};

pub const SeaState = struct {
    /// Significant wave height [m]
    Hs_m: f64,
    /// Mean zero-up-crossing period [s]
    Tz_s: f64,
};

pub const HeaveCoeffs = struct {
    /// Displacement mass [kg]
    M_kg: f64,
    /// Added mass A_33(omega) — constant approximation for narrow band
    A_33: f64,
    /// Damping B_33(omega)
    B_33: f64,
    /// Restoring C_33 = rho g A_w
    C_33: f64,
    /// Excitation |F_3| at reference (Froude-Krylov balance → |F|=C_33 at low omega)
    F_mag: f64,
};

pub const OperabilityLimits = struct {
    max_heave_m: f64 = 2.0,
    max_roll_deg: f64 = 15.0,
};

pub const Input = struct {
    particulars: naval.PrincipalParticulars,
    sea: SeaState,
    heave: HeaveCoeffs,
    limits: OperabilityLimits = .{},
    /// omega grid [rad/s]
    omega_min: f64 = 0.2,
    omega_max: f64 = 2.0,
    omega_step: f64 = 0.1,
    /// RK4 simulation: harmonic excitation at peak omega, duration [s]
    sim_duration_s: f64 = 60.0,
    sim_dt_s: f64 = 0.1,
    constants: naval.PhysicalConstants = .default,
};

pub const MotionStats = struct {
    m0_wave: f64,
    m0_response: f64,
    significant_heave_m: f64,
    mean_zero_crossing_period_s: f64,
    peak_rao: f64,
    peak_omega_rad_s: f64,
};

pub const SimulationStats = struct {
    max_heave_m: f64,
    max_roll_rad: f64,
    operability_pass: bool,
};

pub const Output = struct {
    stats: MotionStats,
    simulation: SimulationStats,
    flags: naval.ValidityFlags,
    proof_level: naval.ProofLevel = .unit_tested,
};

pub fn evaluate(allocator: std.mem.Allocator, input: Input) Error!Output {
    if (input.sea.Hs_m <= 0.0 or input.sea.Tz_s <= 0.0 or input.omega_step <= 0.0)
        return Error.InvalidSeaState;

    const n = @as(usize, @intFromFloat(@floor((input.omega_max - input.omega_min) / input.omega_step))) + 1;
    var omega = try allocator.alloc(f64, n);
    defer allocator.free(omega);
    var s_wave = try allocator.alloc(f64, n);
    defer allocator.free(s_wave);
    var h_mag_sq = try allocator.alloc(f64, n);
    defer allocator.free(h_mag_sq);
    const s_response = try allocator.alloc(f64, n);
    defer allocator.free(s_response);

    const F: strip.heave.Complex = .{ .re = input.heave.F_mag, .im = 0.0 };

    var peak_rao: f64 = 0.0;
    var peak_omega: f64 = input.omega_min;
    var i: usize = 0;
    var w: f64 = input.omega_min;
    while (i < n) : (i += 1) {
        omega[i] = w;
        s_wave[i] = seakeeping.spectra.ittcModifiedPM(w, input.sea.Hs_m, input.sea.Tz_s);
        const rao_m = strip.heave.raoModulus(
            input.heave.M_kg,
            input.heave.A_33,
            input.heave.B_33,
            input.heave.C_33,
            F,
            w,
        ) catch return Error.RAOComputationFailed;
        h_mag_sq[i] = rao_m * rao_m;
        if (rao_m > peak_rao) {
            peak_rao = rao_m;
            peak_omega = w;
        }
        w += input.omega_step;
    }

    rao.spectrum.responseSpectrum(h_mag_sq, s_wave, s_response) catch return Error.SpectrumIntegrationFailed;

    const m0_wave = rao.spectrum.spectralMoment(0, omega, s_wave) catch return Error.SpectrumIntegrationFailed;
    const m0_resp = rao.spectrum.spectralMoment(0, omega, s_response) catch return Error.SpectrumIntegrationFailed;
    const m2_resp = rao.spectrum.spectralMoment(2, omega, s_response) catch return Error.SpectrumIntegrationFailed;

    const sig_heave = rao.spectrum.significantResponseAmplitude(m0_resp);
    const tz_resp = rao.spectrum.meanZeroCrossingPeriod(m0_resp, m2_resp);

    // Short harmonic RK4 simulation at peak frequency (linear regime check).
    const barge = hydro.box_barge.Barge{
        .L = input.particulars.L,
        .B = input.particulars.B,
        .T = input.particulars.T,
    };
    const V = barge.volume();
    const rho = input.constants.rho_seawater;
    const K_z = rho * input.constants.g * (input.particulars.B * input.particulars.L);
    const K_phi = rho * input.constants.g * 0.5 * V * input.particulars.B / input.particulars.T; // crude GM_T proxy

    const params: fossen.fossen.Parameters = .{
        .M_diag = .{
            input.heave.M_kg, input.heave.M_kg, input.heave.M_kg,
            input.heave.M_kg * input.particulars.B * input.particulars.B / 12.0,
            input.heave.M_kg * input.particulars.L * input.particulars.L / 12.0,
            input.heave.M_kg * input.particulars.L * input.particulars.L / 12.0,
        },
        .D_lin = .{ 1.0e4, 1.0e4, input.heave.B_33, 1.0e5, 1.0e5, 1.0e5 },
        .K_z = K_z,
        .K_phi = K_phi,
        .K_theta = K_phi,
    };

    var state: fossen.fossen.State = .{
        .eta = .{ 0, 0, 0, 0, 0, 0 },
        .nu = .{ 0, 0, 0, 0, 0, 0 },
    };

    const n_steps = @as(usize, @intFromFloat(@floor(input.sim_duration_s / input.sim_dt_s)));
    var max_heave: f64 = 0.0;
    var max_roll: f64 = 0.0;
    var t: f64 = 0.0;
    var step: usize = 0;
    const wave_force_z = input.heave.F_mag * input.sea.Hs_m / 2.0; // scaled excitation

    while (step < n_steps) : (step += 1) {
        var tau: [6]f64 = .{ 0, 0, 0, 0, 0, 0 };
        tau[2] = wave_force_z * @sin(peak_omega * t);
        state = fossen.fossen.rk4Step(state, params, tau, input.sim_dt_s) catch return Error.SimulationFailed;
        t += input.sim_dt_s;
        max_heave = @max(max_heave, @abs(state.eta[2]));
        max_roll = @max(max_roll, @abs(state.eta[3]));
    }

    const max_roll_deg = naval.units.radToDeg(max_roll);
    const op_pass = max_heave <= input.limits.max_heave_m and max_roll_deg <= input.limits.max_roll_deg;

    var flags: naval.ValidityFlags = .{};
    flags.insert(.small_angle_regime);
    if (peak_omega * sig_heave < 0.5) flags.insert(.wall_sided_assumption_valid); // linear proxy
    if (!op_pass) flags.insert(.outside_validity_envelope);

    return .{
        .stats = .{
            .m0_wave = m0_wave,
            .m0_response = m0_resp,
            .significant_heave_m = sig_heave,
            .mean_zero_crossing_period_s = tz_resp,
            .peak_rao = peak_rao,
            .peak_omega_rad_s = peak_omega,
        },
        .simulation = .{
            .max_heave_m = max_heave,
            .max_roll_rad = max_roll,
            .operability_pass = op_pass,
        },
        .flags = flags,
    };
}

test "canonical seakeeping assessment produces positive significant heave" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const barge = hydro.box_barge.Barge{ .L = 100.0, .B = 16.0, .T = 6.0 };
    const V = barge.volume();
    const rho: f64 = 1025.0;
    const g: f64 = 9.80665;
    const Aw = 100.0 * 16.0;
    const C_33 = rho * g * Aw;

    const out = try evaluate(arena.allocator(), .{
        .particulars = .{ .L = 100.0, .B = 16.0, .T = 6.0 },
        .sea = .{ .Hs_m = 2.0, .Tz_s = 8.0 },
        .heave = .{
            .M_kg = rho * V,
            .A_33 = 0.2 * rho * V,
            .B_33 = 5.0e5,
            .C_33 = C_33,
            .F_mag = C_33,
        },
        .limits = .{ .max_heave_m = 5.0, .max_roll_deg = 30.0 },
    });

    try std.testing.expect(out.stats.significant_heave_m > 0.0);
    try std.testing.expect(out.stats.peak_rao > 0.0);
    try std.testing.expect(out.stats.m0_response > 0.0);
}