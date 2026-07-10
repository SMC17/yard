//! First-order Nomoto steering model and IMO trial prediction.
//!
//!   T r' + r = K delta        (yaw rate r, rudder delta)
//!
//! Nondimensional indices K' = K L / V, T' = T V / L (Nomoto 1957). RK4 at
//! fixed nondimensional step — deterministic. The rudder actuator slews at
//! a finite rate (IMO trials assume ~2.3 deg/s typical steering gear).

const std = @import("std");

pub const Indices = struct {
    k_prime: f64,
    t_prime: f64,
};

/// Steady turning diameter for rudder angle delta [deg], from r_ss = K delta:
///   D = 2 V / r_ss = 2 L / (K' delta_rad).
pub fn steadyTurningDiameterM(idx: Indices, length_m: f64, rudder_deg: f64) f64 {
    const delta_rad = std.math.degreesToRadians(rudder_deg);
    return 2.0 * length_m / (idx.k_prime * delta_rad);
}

pub const ZigZag = struct {
    first_overshoot_deg: f64,
    second_overshoot_deg: f64,
};

/// Simulate a psi_cmd/psi_cmd zig-zag (e.g. 10/10). Time, rates
/// nondimensional (t' = t V / L); rudder slew ~2.3 deg/s expressed via
/// slew' = slew * L / V using a reference L/V of 20 s baked into the
/// default; callers can override.
pub fn zigzag(idx: Indices, cmd_deg: f64, rudder_slew_deg_per_tprime: f64) ZigZag {
    const dt: f64 = 0.005;
    var psi: f64 = 0; // heading [deg]
    var r: f64 = 0; // yaw rate [deg / t']
    var delta: f64 = 0; // rudder [deg]
    var target: f64 = cmd_deg;
    var phase: u32 = 0; // 0: first leg, 1: second leg, 2: third leg
    var first_os: f64 = 0;
    var second_os: f64 = 0;
    var t: f64 = 0;

    while (t < 200.0 and phase < 3) : (t += dt) {
        // Rudder slews toward target.
        const d_err = target - delta;
        const max_step = rudder_slew_deg_per_tprime * dt;
        delta += std.math.clamp(d_err, -max_step, max_step);

        // T' r' + r = K' delta, integrated with RK4 (linear, so exact
        // enough at this step; RK4 keeps it honest if T' is small).
        const f = struct {
            fn dr(kp: f64, tp: f64, dl: f64, rr: f64) f64 {
                return (kp * dl - rr) / tp;
            }
        }.dr;
        const k1 = f(idx.k_prime, idx.t_prime, delta, r);
        const k2 = f(idx.k_prime, idx.t_prime, delta, r + 0.5 * dt * k1);
        const k3 = f(idx.k_prime, idx.t_prime, delta, r + 0.5 * dt * k2);
        const k4 = f(idx.k_prime, idx.t_prime, delta, r + dt * k3);
        r += dt / 6.0 * (k1 + 2 * k2 + 2 * k3 + k4);
        psi += r * dt;

        switch (phase) {
            0 => {
                if (psi >= cmd_deg) {
                    target = -cmd_deg;
                    phase = 1;
                }
            },
            1 => {
                if (psi - cmd_deg > first_os) first_os = psi - cmd_deg;
                if (psi <= -cmd_deg) {
                    target = cmd_deg;
                    phase = 2;
                }
            },
            2 => {
                if (-cmd_deg - psi > second_os) second_os = -cmd_deg - psi;
                if (psi >= 0) phase = 3;
            },
            else => {},
        }
    }
    return .{ .first_overshoot_deg = first_os, .second_overshoot_deg = second_os };
}

/// Default rudder slew: 2.3 deg/s at L/V = 20 s -> 46 deg per t'.
pub const default_slew: f64 = 46.0;

test "steady turning diameter scales as stated" {
    const idx = Indices{ .k_prime = 0.2, .t_prime = 3.0 };
    const d35 = steadyTurningDiameterM(idx, 150.0, 35.0);
    // 2*150 / (0.2 * 0.6109) = 2455 m.
    try std.testing.expectApproxEqAbs(@as(f64, 2455.0), d35, 2.0);
    // Doubling K' halves the diameter; halving rudder doubles it.
    try std.testing.expectApproxEqAbs(d35 / 2.0, steadyTurningDiameterM(.{ .k_prime = 0.4, .t_prime = 3.0 }, 150.0, 35.0), 2.0);
    try std.testing.expectApproxEqAbs(d35 * 2.0, steadyTurningDiameterM(idx, 150.0, 17.5), 4.0);
}

test "zig-zag overshoot grows with T' (sluggisher ship overshoots more)" {
    const quick = zigzag(.{ .k_prime = 0.2, .t_prime = 1.5 }, 10.0, default_slew);
    const slow = zigzag(.{ .k_prime = 0.2, .t_prime = 4.0 }, 10.0, default_slew);
    const very_slow = zigzag(.{ .k_prime = 0.2, .t_prime = 8.0 }, 10.0, default_slew);
    try std.testing.expect(slow.first_overshoot_deg > quick.first_overshoot_deg);
    try std.testing.expect(very_slow.first_overshoot_deg > slow.first_overshoot_deg);
    try std.testing.expect(quick.first_overshoot_deg > 0);
}

test "overshoot grows with K' at fixed T'" {
    const weak = zigzag(.{ .k_prime = 0.15, .t_prime = 3.0 }, 10.0, default_slew);
    const strong = zigzag(.{ .k_prime = 0.35, .t_prime = 3.0 }, 10.0, default_slew);
    try std.testing.expect(strong.first_overshoot_deg > weak.first_overshoot_deg);
}

test "a responsive cargo-ship parameterization meets the 10/10 criterion" {
    // K' 0.2, T' 2: a stable, well-steered hull. L/V = 19.5 s -> limit 14.7.
    const os = zigzag(.{ .k_prime = 0.2, .t_prime = 2.0 }, 10.0, default_slew);
    const criteria = @import("criteria.zig");
    const limit = criteria.zigzag1010FirstOvershootLimit(19.5);
    try std.testing.expect(os.first_overshoot_deg < limit);
    try std.testing.expect(os.second_overshoot_deg < criteria.zigzag1010SecondOvershootLimit(19.5));
}
