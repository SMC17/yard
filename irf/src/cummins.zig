const std = @import("std");

pub const Error = error{
    UnequalLength,
    InsufficientPoints,
    NonUniformSpacing,
    OmegaNotSorted,
    NonPositiveMass,
    NonPositiveStep,
    OmegaRefOutOfBand,
};

/// Retardation function K(t) for a single frequency-row evaluation:
///   K(t) = (2/pi) integral_0^omega_max B(omega) cos(omega t) domega
/// evaluated via trapezoidal quadrature on the caller-supplied
/// uniformly spaced omega grid.
pub fn retardationFunctionAtT(
    omega_arr: []const f64,
    B_arr: []const f64,
    t: f64,
) Error!f64 {
    if (omega_arr.len != B_arr.len) return Error.UnequalLength;
    if (omega_arr.len < 2) return Error.InsufficientPoints;
    var i: usize = 1;
    while (i < omega_arr.len) : (i += 1) {
        if (!(omega_arr[i] > omega_arr[i - 1])) return Error.OmegaNotSorted;
    }
    const dw = omega_arr[1] - omega_arr[0];
    const tol = 1e-9 * @max(@abs(dw), 1.0);
    var k: usize = 1;
    while (k < omega_arr.len - 1) : (k += 1) {
        const r = (omega_arr[k + 1] - omega_arr[k]) - dw;
        if (@abs(r) > tol) return Error.NonUniformSpacing;
    }
    // Trapezoidal rule on B(omega) cos(omega t).
    var sum: f64 = 0.0;
    sum += 0.5 * B_arr[0] * @cos(omega_arr[0] * t);
    sum += 0.5 * B_arr[omega_arr.len - 1] * @cos(omega_arr[omega_arr.len - 1] * t);
    var j: usize = 1;
    while (j < omega_arr.len - 1) : (j += 1) {
        sum += B_arr[j] * @cos(omega_arr[j] * t);
    }
    sum *= dw;
    return 2.0 / std.math.pi * sum;
}

/// Build the retardation array K(t_i) for an output time grid t_arr.
/// Caller supplies the omega grid B(omega) and the output buffer.
pub fn buildRetardationArray(
    omega_arr: []const f64,
    B_arr: []const f64,
    t_arr: []const f64,
    K_out: []f64,
) Error!void {
    if (t_arr.len != K_out.len) return Error.UnequalLength;
    var i: usize = 0;
    while (i < t_arr.len) : (i += 1) {
        K_out[i] = try retardationFunctionAtT(omega_arr, B_arr, t_arr[i]);
    }
}

/// Recover A_infinity from a reference frequency omega_ref and the
/// already-computed K(t) array on a uniformly-spaced t grid:
///   A_inf = A(omega_ref) - (1 / omega_ref) integral_0^T_max
///                          K(tau) sin(omega_ref * tau) dtau.
/// Trapezoidal quadrature on the t grid; caller is responsible for
/// T_max large enough that K decays toward zero.
pub fn addedMassInfinity(
    A_at_ref: f64,
    omega_ref: f64,
    t_arr: []const f64,
    K_arr: []const f64,
) Error!f64 {
    if (!(omega_ref > 0)) return Error.OmegaRefOutOfBand;
    if (t_arr.len != K_arr.len) return Error.UnequalLength;
    if (t_arr.len < 2) return Error.InsufficientPoints;
    const dt = t_arr[1] - t_arr[0];
    const tol = 1e-9 * @max(@abs(dt), 1.0);
    var k: usize = 1;
    while (k < t_arr.len - 1) : (k += 1) {
        const r = (t_arr[k + 1] - t_arr[k]) - dt;
        if (@abs(r) > tol) return Error.NonUniformSpacing;
    }
    var sum: f64 = 0.0;
    sum += 0.5 * K_arr[0] * @sin(omega_ref * t_arr[0]);
    sum += 0.5 * K_arr[K_arr.len - 1] * @sin(omega_ref * t_arr[t_arr.len - 1]);
    var j: usize = 1;
    while (j < K_arr.len - 1) : (j += 1) {
        sum += K_arr[j] * @sin(omega_ref * t_arr[j]);
    }
    sum *= dt;
    return A_at_ref - sum / omega_ref;
}

/// Single forward-Euler step of the Cummins equation:
///   [M + A_inf] ddot{x} = F(t) - C x - integral_0^t K(t - tau) dot{x} dtau
/// using a discrete convolution on the velocity history. Returns the
/// new (x, v) pair after time step dt.
pub fn cumminsStep(
    M_eff_kg: f64,
    C_n_per_m: f64,
    F_t: f64,
    x: f64,
    v: f64,
    /// Memory term integral_0^t K(t - tau) dot{x}(tau) dtau.
    mem: f64,
    dt: f64,
) Error!struct { x: f64, v: f64 } {
    if (!(M_eff_kg > 0)) return Error.NonPositiveMass;
    if (!(dt > 0)) return Error.NonPositiveStep;
    const a = (F_t - C_n_per_m * x - mem) / M_eff_kg;
    const v_new = v + a * dt;
    const x_new = x + v_new * dt;
    return .{ .x = x_new, .v = v_new };
}

test "K(0) equals (2/pi) integral B(omega) domega for constant B" {
    // Build omega grid 0.1..3.0 step 0.05, B = 5.0.
    var omega: [59]f64 = undefined;
    var B: [59]f64 = undefined;
    var i: usize = 0;
    while (i < omega.len) : (i += 1) {
        omega[i] = 0.1 + 0.05 * @as(f64, @floatFromInt(i));
        B[i] = 5.0;
    }
    const K0 = try retardationFunctionAtT(&omega, &B, 0.0);
    // Exact: (2/pi) * 5 * (3.0 - 0.1) = (2/pi) * 14.5 = 9.23028...
    const expected = (2.0 / std.math.pi) * 5.0 * (omega[omega.len - 1] - omega[0]);
    // Trapezoidal rule on uniform grid with constant integrand is exact.
    try std.testing.expectApproxEqAbs(expected, K0, 1e-9);
}

test "K(t) for B(omega) = delta-bump approximation" {
    // B(omega) sharply peaked at omega_p = 1.0 then K(t) ~ (2/pi) Bp dw cos(omega_p t).
    var omega: [41]f64 = undefined;
    var B: [41]f64 = undefined;
    var i: usize = 0;
    while (i < omega.len) : (i += 1) {
        omega[i] = 0.5 + 0.025 * @as(f64, @floatFromInt(i));
        B[i] = 0.0;
    }
    B[20] = 100.0; // omega ~ 0.5 + 0.025 * 20 = 1.0
    const t: f64 = 5.0;
    const K = try retardationFunctionAtT(&omega, &B, t);
    // Approximate: K(t) ~ (2/pi) * 100 * 0.025 * cos(1.0 * 5.0).
    const expected_approx = (2.0 / std.math.pi) * 100.0 * 0.025 * @cos(1.0 * 5.0);
    try std.testing.expectApproxEqAbs(expected_approx, K, 0.1);
}

test "buildRetardationArray populates t-grid" {
    var omega: [21]f64 = undefined;
    var B: [21]f64 = undefined;
    var i: usize = 0;
    while (i < omega.len) : (i += 1) {
        omega[i] = 0.1 + 0.1 * @as(f64, @floatFromInt(i));
        B[i] = 5.0;
    }
    var t_arr: [10]f64 = undefined;
    var K_out: [10]f64 = undefined;
    var j: usize = 0;
    while (j < t_arr.len) : (j += 1) {
        t_arr[j] = 0.5 * @as(f64, @floatFromInt(j));
    }
    try buildRetardationArray(&omega, &B, &t_arr, &K_out);
    // K(0) should be the largest in magnitude.
    var k: usize = 1;
    while (k < K_out.len) : (k += 1) {
        try std.testing.expect(@abs(K_out[0]) >= @abs(K_out[k]) - 1e-3);
    }
}

test "added-mass infinity: zero K array returns A_at_ref" {
    var t_arr: [21]f64 = undefined;
    var K_arr: [21]f64 = undefined;
    var i: usize = 0;
    while (i < t_arr.len) : (i += 1) {
        t_arr[i] = 0.1 * @as(f64, @floatFromInt(i));
        K_arr[i] = 0.0;
    }
    const A_inf = try addedMassInfinity(2500.0, 1.0, &t_arr, &K_arr);
    try std.testing.expectApproxEqAbs(@as(f64, 2500.0), A_inf, 1e-9);
}

test "Cummins step: zero memory + zero stiffness gives ballistic motion" {
    // M_eff * a = F -> a = F/M.
    const step = try cumminsStep(1000.0, 0.0, 100.0, 0.0, 0.0, 0.0, 0.1);
    // v_new = 0 + 0.1 * 0.1 = 0.01; x_new = 0 + 0.01 * 0.1 = 0.001.
    try std.testing.expectApproxEqAbs(@as(f64, 0.01), step.v, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.001), step.x, 1e-12);
}

test "Cummins step: linear restoring decelerates motion" {
    // M = 1, C = 10, no memory, F = 0, x = 1, v = 0.
    const step = try cumminsStep(1.0, 10.0, 0.0, 1.0, 0.0, 0.0, 0.01);
    // a = -10 * 1 = -10. v_new = -0.1. x_new = 1 + (-0.1) * 0.01 = 0.999.
    try std.testing.expectApproxEqAbs(@as(f64, -0.1), step.v, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.999), step.x, 1e-12);
}

test "Cummins step: memory force opposes motion" {
    // Same setup but mem = 5.0. a = (0 - 10*1 - 5)/1 = -15. v = -0.15.
    const step = try cumminsStep(1.0, 10.0, 0.0, 1.0, 0.0, 5.0, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, -0.15), step.v, 1e-12);
}

test "input rejection: non-positive M_eff" {
    try std.testing.expectError(
        Error.NonPositiveMass,
        cumminsStep(0.0, 10.0, 0.0, 1.0, 0.0, 0.0, 0.01),
    );
}

test "input rejection: non-positive dt" {
    try std.testing.expectError(
        Error.NonPositiveStep,
        cumminsStep(1.0, 10.0, 0.0, 1.0, 0.0, 0.0, 0.0),
    );
}

test "input rejection: unequal-length omega and B" {
    const omega = [_]f64{ 0.1, 0.2, 0.3, 0.4 };
    const B = [_]f64{ 1.0, 2.0 };
    try std.testing.expectError(Error.UnequalLength, retardationFunctionAtT(&omega, &B, 0.0));
}

test "input rejection: omega_ref non-positive" {
    const t_arr = [_]f64{ 0.0, 0.1, 0.2, 0.3, 0.4 };
    const K_arr = [_]f64{ 1.0, 0.5, 0.2, 0.1, 0.05 };
    try std.testing.expectError(Error.OmegaRefOutOfBand, addedMassInfinity(100.0, 0.0, &t_arr, &K_arr));
}
