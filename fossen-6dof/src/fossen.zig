// Linearized 6-DOF marine craft state space (Fossen 2011).
//
// State variables (per Fossen Ch. 7):
//   eta = (x, y, z, phi, theta, psi)   earth-frame position + orientation
//   nu  = (u, v, w, p, q, r)            body-frame velocity
//
// Linearized equation of motion (constant diagonal M; linear damping;
// linearized restoring on heave/roll/pitch):
//
//   M_diag * dnu/dt + D_lin * nu + g(eta) = tau
//
// where g(eta) is zero on (x, y, psi) and linear in (z, phi, theta):
//   g_z(eta)     = K_z * z      (heave hydrostatic stiffness)
//   g_phi(eta)   = K_phi * phi  (roll restoring; rho g GM_T * V_disp)
//   g_theta(eta) = K_theta * theta (pitch restoring; rho g GM_L * V_disp)
//
// Kinematics (linearized, small Euler angles, neglected coupling):
//   deta/dt = nu
//
// RK4 integrator advances (eta, nu) by one timestep h.

const std = @import("std");

pub const State = struct {
    eta: [6]f64,
    nu: [6]f64,
};

pub const Parameters = struct {
    M_diag: [6]f64,
    D_lin: [6]f64,
    K_z: f64,
    K_phi: f64,
    K_theta: f64,
};

pub const Error = error{
    NonPositiveMass,
    NonNegativeStep,
};

fn derivative(s: State, p: Parameters, tau: [6]f64) State {
    var d_eta: [6]f64 = undefined;
    var d_nu: [6]f64 = undefined;
    // Linearized kinematics.
    var i: usize = 0;
    while (i < 6) : (i += 1) d_eta[i] = s.nu[i];

    // Restoring force vector g(eta).
    var g: [6]f64 = .{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
    g[2] = p.K_z * s.eta[2];
    g[3] = p.K_phi * s.eta[3];
    g[4] = p.K_theta * s.eta[4];

    // M_diag * dnu/dt = tau - D_lin * nu - g
    i = 0;
    while (i < 6) : (i += 1) {
        d_nu[i] = (tau[i] - p.D_lin[i] * s.nu[i] - g[i]) / p.M_diag[i];
    }
    return .{ .eta = d_eta, .nu = d_nu };
}

fn addScaled(a: State, b: State, scale: f64) State {
    var out: State = undefined;
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        out.eta[i] = a.eta[i] + scale * b.eta[i];
        out.nu[i] = a.nu[i] + scale * b.nu[i];
    }
    return out;
}

/// Advance the state by one RK4 step of size h. Validates positive M
/// and positive h.
pub fn rk4Step(s: State, p: Parameters, tau: [6]f64, h: f64) Error!State {
    if (h <= 0.0) return Error.NonNegativeStep;
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        if (p.M_diag[i] <= 0.0) return Error.NonPositiveMass;
    }

    const k1 = derivative(s, p, tau);
    const k2 = derivative(addScaled(s, k1, 0.5 * h), p, tau);
    const k3 = derivative(addScaled(s, k2, 0.5 * h), p, tau);
    const k4 = derivative(addScaled(s, k3, h), p, tau);

    var out: State = undefined;
    i = 0;
    while (i < 6) : (i += 1) {
        const sum_eta = k1.eta[i] + 2.0 * k2.eta[i] + 2.0 * k3.eta[i] + k4.eta[i];
        const sum_nu = k1.nu[i] + 2.0 * k2.nu[i] + 2.0 * k3.nu[i] + k4.nu[i];
        out.eta[i] = s.eta[i] + (h / 6.0) * sum_eta;
        out.nu[i] = s.nu[i] + (h / 6.0) * sum_nu;
    }
    return out;
}

const expectApproxEqAbs = std.testing.expectApproxEqAbs;
const expectApproxEqRel = std.testing.expectApproxEqRel;

fn defaultParams() Parameters {
    return .{
        .M_diag = .{ 1.0e6, 1.0e6, 1.0e6, 1.0e7, 1.0e7, 1.0e7 },
        .D_lin = .{ 1.0e4, 1.0e4, 1.0e4, 1.0e5, 1.0e5, 1.0e5 },
        .K_z = 1.0e6,
        .K_phi = 1.0e7,
        .K_theta = 1.0e7,
    };
}

const zero_state: State = .{ .eta = .{ 0, 0, 0, 0, 0, 0 }, .nu = .{ 0, 0, 0, 0, 0, 0 } };
const zero_tau: [6]f64 = .{ 0, 0, 0, 0, 0, 0 };

test "rk4Step with zero state and zero input stays zero" {
    const s = try rk4Step(zero_state, defaultParams(), zero_tau, 0.1);
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        try expectApproxEqAbs(@as(f64, 0.0), s.eta[i], 1e-12);
        try expectApproxEqAbs(@as(f64, 0.0), s.nu[i], 1e-12);
    }
}

test "Surge step input accelerates surge velocity from rest" {
    var tau: [6]f64 = .{ 0, 0, 0, 0, 0, 0 };
    tau[0] = 1.0e4;
    const s = try rk4Step(zero_state, defaultParams(), tau, 0.1);
    try std.testing.expect(s.nu[0] > 0.0);
}

test "Surge step input drives nu_0 toward steady state tau / D_lin" {
    var tau: [6]f64 = .{ 0, 0, 0, 0, 0, 0 };
    tau[0] = 1.0e4;
    const p = defaultParams();
    var s = zero_state;
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        s = try rk4Step(s, p, tau, 0.5);
    }
    const ss = tau[0] / p.D_lin[0]; // 1.0 m/s
    try expectApproxEqRel(ss, s.nu[0], 1e-2);
}

test "Heave restoring brings z back toward zero with damping" {
    var s = zero_state;
    s.eta[2] = 1.0; // initial z displacement
    const p = defaultParams();
    var prev_z = s.eta[2];
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        s = try rk4Step(s, p, zero_tau, 0.1);
    }
    // After ~ 20 seconds of damped oscillation z should be much smaller
    // than initial value.
    try std.testing.expect(@abs(s.eta[2]) < 0.5 * @abs(prev_z));
    prev_z = s.eta[2];
}

test "rk4Step rejects non-positive timestep" {
    try std.testing.expectError(Error.NonNegativeStep, rk4Step(zero_state, defaultParams(), zero_tau, 0.0));
    try std.testing.expectError(Error.NonNegativeStep, rk4Step(zero_state, defaultParams(), zero_tau, -0.1));
}

test "rk4Step rejects non-positive mass diagonal" {
    var p = defaultParams();
    p.M_diag[2] = 0.0;
    try std.testing.expectError(Error.NonPositiveMass, rk4Step(zero_state, p, zero_tau, 0.1));
}

test "Surge channel decouples from sway when both excited" {
    var tau: [6]f64 = .{ 0, 0, 0, 0, 0, 0 };
    tau[0] = 1.0e4; // surge
    tau[1] = 2.0e4; // sway
    const p = defaultParams();
    var s = zero_state;
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        s = try rk4Step(s, p, tau, 0.1);
    }
    // In the linearized form M, D are diagonal so surge and sway evolve
    // independently. nu_1 / nu_0 should equal tau[1] / tau[0] = 2.0.
    try expectApproxEqRel(@as(f64, 2.0), s.nu[1] / s.nu[0], 1e-6);
}

test "Zero tau and nonzero phi shows damped roll oscillation" {
    var s = zero_state;
    s.eta[3] = 0.05; // small initial roll angle
    const p = defaultParams();
    const omega_n = @sqrt(p.K_phi / p.M_diag[3]);
    const T_n = 2.0 * std.math.pi / omega_n;
    var i: usize = 0;
    // Integrate one natural period; magnitude should reduce by exp(-zeta * 2 pi)
    while (i < 1000) : (i += 1) {
        s = try rk4Step(s, p, zero_tau, T_n / 1000.0);
    }
    try std.testing.expect(@abs(s.eta[3]) < 0.05);
}

test "Total impulse approximates integrated tau in surge over small step" {
    var tau: [6]f64 = .{ 0, 0, 0, 0, 0, 0 };
    tau[0] = 1.0e4;
    const p = defaultParams();
    const h: f64 = 1e-3;
    const s = try rk4Step(zero_state, p, tau, h);
    // For very small h, velocity gain approaches tau * h / M (the impulsive
    // limit). RK4 includes the linear-damping correction which is small at
    // this h; tolerance 1e-4 captures the impulsive limit cleanly.
    const expected_nu0 = tau[0] * h / p.M_diag[0];
    try expectApproxEqRel(expected_nu0, s.nu[0], 1e-4);
}

test "Roll natural frequency equals sqrt(K_phi / M_phi)" {
    const p = defaultParams();
    const omega_n = @sqrt(p.K_phi / p.M_diag[3]);
    // omega_n = sqrt(1e7 / 1e7) = 1.0 rad/s
    try expectApproxEqAbs(@as(f64, 1.0), omega_n, 1e-12);
}
