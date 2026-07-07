const std = @import("std");

pub const Error = error{
    NonPositiveInertia,
    NonPositiveStiffness,
    InsufficientStations,
    UnequalLength,
    NonPositiveOmega,
    NoConvergence,
};

/// Holzer residual T_end(omega): given inertias J[0..N-1] and springs
/// k[0..N-2] between stations, propagate amplitude phi and torque T
/// from the free end (phi_0 = 1, T_0 = 0) through the chain.
///   T_i = T_{i-1} - J_i omega^2 phi_{i-1}    is wrong; the proper
/// Holzer table is:
///   phi_0 = 1
///   T_0 = J_0 omega^2 phi_0
///   phi_1 = phi_0 + T_0 / k_0
///   T_1 = T_0 + J_1 omega^2 phi_1
///   ...
///   phi_{N-1} = phi_{N-2} + T_{N-2} / k_{N-2}
///   T_{N-1} = T_{N-2} + J_{N-1} omega^2 phi_{N-1}
/// The residual is T_{N-1}; a natural frequency satisfies T_{N-1} = 0.
pub fn holzerResidual(
    J: []const f64,
    k: []const f64,
    omega: f64,
) Error!f64 {
    if (J.len < 2) return Error.InsufficientStations;
    if (k.len + 1 != J.len) return Error.UnequalLength;
    if (!(omega > 0)) return Error.NonPositiveOmega;
    for (J) |j| if (!(j > 0)) return Error.NonPositiveInertia;
    for (k) |ki| if (!(ki > 0)) return Error.NonPositiveStiffness;
    var phi: f64 = 1.0;
    var T: f64 = J[0] * omega * omega * phi;
    var i: usize = 1;
    while (i < J.len) : (i += 1) {
        // Spring twist: the cumulative inertia torque T must produce
        // a counter-twist in the next station so that the spring
        // provides the restoring force. Sign convention per the
        // classical free-free Holzer table (Den Hartog 1956 Ch. 4).
        phi = phi - T / k[i - 1];
        T = T + J[i] * omega * omega * phi;
    }
    return T;
}

/// Locate the lowest natural frequency by bracketing the sign change
/// of `holzerResidual` and refining via bisection on
/// [omega_lo, omega_hi]. Caller chooses the bracket; for a typical
/// shaftline the first mode lies in 50..500 rad/s.
pub fn findNaturalFrequency(
    J: []const f64,
    k: []const f64,
    omega_lo_rps: f64,
    omega_hi_rps: f64,
) Error!f64 {
    if (!(omega_lo_rps > 0)) return Error.NonPositiveOmega;
    if (!(omega_hi_rps > omega_lo_rps)) return Error.NoConvergence;
    var lo = omega_lo_rps;
    var hi = omega_hi_rps;
    const r_lo = try holzerResidual(J, k, lo);
    const r_hi = try holzerResidual(J, k, hi);
    if (r_lo * r_hi >= 0.0) return Error.NoConvergence;
    var iter: usize = 0;
    while (iter < 200) : (iter += 1) {
        const mid = 0.5 * (lo + hi);
        const r_mid = try holzerResidual(J, k, mid);
        if (r_mid * r_lo <= 0.0) {
            hi = mid;
        } else {
            lo = mid;
        }
        if ((hi - lo) / @max(hi, 1.0) < 1e-10) return 0.5 * (lo + hi);
    }
    return Error.NoConvergence;
}

test "two-station system: omega_1 = sqrt(k (J_1 + J_2) / (J_1 J_2))" {
    // Classical two-inertia system: J_1 = 10, J_2 = 5, k = 1e6.
    // omega_1^2 = k * (J_1 + J_2) / (J_1 J_2) = 1e6 * 15 / 50 = 3e5
    // omega_1 = sqrt(3e5) = 547.72 rad/s.
    const J = [_]f64{ 10.0, 5.0 };
    const k = [_]f64{1.0e6};
    const omega_expected = @sqrt(1.0e6 * 15.0 / 50.0);
    const omega = try findNaturalFrequency(&J, &k, 100.0, 1000.0);
    try std.testing.expectApproxEqAbs(omega_expected, omega, 1.0e-4);
}

test "Holzer residual is zero at the natural frequency" {
    const J = [_]f64{ 10.0, 5.0 };
    const k = [_]f64{1.0e6};
    const omega = @sqrt(1.0e6 * 15.0 / 50.0);
    const r = try holzerResidual(&J, &k, omega);
    try std.testing.expect(@abs(r) < 1e-6);
}

test "Holzer residual at low omega is positive (mass dominated)" {
    const J = [_]f64{ 10.0, 5.0 };
    const k = [_]f64{1.0e6};
    const r = try holzerResidual(&J, &k, 10.0);
    try std.testing.expect(r > 0);
}

test "Holzer residual at high omega has opposite sign" {
    const J = [_]f64{ 10.0, 5.0 };
    const k = [_]f64{1.0e6};
    const r_lo = try holzerResidual(&J, &k, 10.0);
    const r_hi = try holzerResidual(&J, &k, 1000.0);
    try std.testing.expect(r_lo * r_hi < 0);
}

test "three-inertia system has lowest natural frequency between bound" {
    // J_1=10, J_2=5, J_3=2, k_1=1e6, k_2=5e5.
    const J = [_]f64{ 10.0, 5.0, 2.0 };
    const k = [_]f64{ 1.0e6, 5.0e5 };
    const omega = try findNaturalFrequency(&J, &k, 50.0, 600.0);
    try std.testing.expect(omega > 50.0 and omega < 600.0);
    const r = try holzerResidual(&J, &k, omega);
    try std.testing.expect(@abs(r) < 1.0);
}

test "Holzer rejects insufficient stations" {
    const J = [_]f64{10.0};
    const k = [_]f64{};
    try std.testing.expectError(Error.InsufficientStations, holzerResidual(&J, &k, 100.0));
}

test "Holzer rejects unequal length" {
    const J = [_]f64{ 10.0, 5.0, 2.0 };
    const k = [_]f64{1.0e6};
    try std.testing.expectError(Error.UnequalLength, holzerResidual(&J, &k, 100.0));
}

test "Holzer rejects non-positive inertia" {
    const J = [_]f64{ 10.0, 0.0 };
    const k = [_]f64{1.0e6};
    try std.testing.expectError(Error.NonPositiveInertia, holzerResidual(&J, &k, 100.0));
}

test "natural-frequency search rejects bracket with no sign change" {
    const J = [_]f64{ 10.0, 5.0 };
    const k = [_]f64{1.0e6};
    try std.testing.expectError(Error.NoConvergence, findNaturalFrequency(&J, &k, 10.0, 50.0));
}
