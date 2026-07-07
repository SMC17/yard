const std = @import("std");

pub const Error = error{
    SingularConfigurationMatrix,
    TooManyThrusters,
    NonPositiveCount,
};

pub const max_thrusters: usize = 8;

/// Thruster geometry: thrust-axis angle from body x-axis (positive
/// counter-clockwise looking down) and lever arm (x, y) of the
/// thrust line of action from the centre of rotation.
pub const Thruster = struct {
    alpha_rad: f64,
    x_m: f64,
    y_m: f64,
};

/// Body-frame demand: surge X [N], sway Y [N], yaw moment N [N m].
pub const Demand = struct {
    X_n: f64,
    Y_n: f64,
    N_nm: f64,
};

/// Build the [3 x N] configuration matrix B and return its column
/// triples (cos alpha_i, sin alpha_i, x_i sin alpha_i - y_i cos alpha_i).
fn buildB(thrusters: []const Thruster, B: *[3][max_thrusters]f64) Error!void {
    if (thrusters.len == 0) return Error.NonPositiveCount;
    if (thrusters.len > max_thrusters) return Error.TooManyThrusters;
    for (thrusters, 0..) |t, i| {
        B[0][i] = @cos(t.alpha_rad);
        B[1][i] = @sin(t.alpha_rad);
        B[2][i] = t.x_m * @sin(t.alpha_rad) - t.y_m * @cos(t.alpha_rad);
    }
}

/// Solve a 3x3 symmetric positive-definite linear system via direct
/// inverse. Returns Error.SingularConfigurationMatrix if the
/// determinant is below the numerical threshold.
fn solve3x3(A: [3][3]f64, rhs: [3]f64) Error![3]f64 {
    const det =
        A[0][0] * (A[1][1] * A[2][2] - A[1][2] * A[2][1]) -
        A[0][1] * (A[1][0] * A[2][2] - A[1][2] * A[2][0]) +
        A[0][2] * (A[1][0] * A[2][1] - A[1][1] * A[2][0]);
    if (@abs(det) < 1e-18) return Error.SingularConfigurationMatrix;
    const inv_det = 1.0 / det;
    var inv: [3][3]f64 = undefined;
    inv[0][0] = (A[1][1] * A[2][2] - A[1][2] * A[2][1]) * inv_det;
    inv[0][1] = (A[0][2] * A[2][1] - A[0][1] * A[2][2]) * inv_det;
    inv[0][2] = (A[0][1] * A[1][2] - A[0][2] * A[1][1]) * inv_det;
    inv[1][0] = (A[1][2] * A[2][0] - A[1][0] * A[2][2]) * inv_det;
    inv[1][1] = (A[0][0] * A[2][2] - A[0][2] * A[2][0]) * inv_det;
    inv[1][2] = (A[0][2] * A[1][0] - A[0][0] * A[1][2]) * inv_det;
    inv[2][0] = (A[1][0] * A[2][1] - A[1][1] * A[2][0]) * inv_det;
    inv[2][1] = (A[0][1] * A[2][0] - A[0][0] * A[2][1]) * inv_det;
    inv[2][2] = (A[0][0] * A[1][1] - A[0][1] * A[1][0]) * inv_det;
    return .{
        inv[0][0] * rhs[0] + inv[0][1] * rhs[1] + inv[0][2] * rhs[2],
        inv[1][0] * rhs[0] + inv[1][1] * rhs[1] + inv[1][2] * rhs[2],
        inv[2][0] * rhs[0] + inv[2][1] * rhs[1] + inv[2][2] * rhs[2],
    };
}

/// Minimum-energy thrust allocation:
///   u = B^T (B B^T)^(-1) tau.
/// Caller supplies the output buffer of length thrusters.len.
pub fn allocate(thrusters: []const Thruster, tau: Demand, u_out: []f64) Error!void {
    const N = thrusters.len;
    if (N == 0) return Error.NonPositiveCount;
    if (N > max_thrusters) return Error.TooManyThrusters;
    if (u_out.len != N) return Error.NonPositiveCount;
    var B: [3][max_thrusters]f64 = undefined;
    try buildB(thrusters, &B);
    // Compute B B^T [3x3].
    var BBT: [3][3]f64 = undefined;
    inline for (0..3) |i| {
        inline for (0..3) |j| {
            var s: f64 = 0.0;
            var k: usize = 0;
            while (k < N) : (k += 1) {
                s += B[i][k] * B[j][k];
            }
            BBT[i][j] = s;
        }
    }
    const lambda = try solve3x3(BBT, .{ tau.X_n, tau.Y_n, tau.N_nm });
    // u = B^T lambda.
    var i: usize = 0;
    while (i < N) : (i += 1) {
        u_out[i] = B[0][i] * lambda[0] + B[1][i] * lambda[1] + B[2][i] * lambda[2];
    }
}

/// Verify the allocation by computing tau_actual = B u and returning
/// the closing residual norm sqrt((X-X_act)^2 + (Y-Y_act)^2 + (N-N_act)^2).
pub fn closingResidual(thrusters: []const Thruster, u: []const f64, tau: Demand) Error!f64 {
    const N = thrusters.len;
    if (N != u.len) return Error.NonPositiveCount;
    var X_act: f64 = 0.0;
    var Y_act: f64 = 0.0;
    var N_act: f64 = 0.0;
    for (thrusters, 0..) |t, i| {
        const c = @cos(t.alpha_rad);
        const s = @sin(t.alpha_rad);
        X_act += c * u[i];
        Y_act += s * u[i];
        N_act += (t.x_m * s - t.y_m * c) * u[i];
    }
    const dX = tau.X_n - X_act;
    const dY = tau.Y_n - Y_act;
    const dN = tau.N_nm - N_act;
    return @sqrt(dX * dX + dY * dY + dN * dN);
}

test "three-thruster fully determined allocation: bow + two stern azimuths" {
    // Bow tunnel (alpha = pi/2, x = +L/2, y = 0); two stern azimuth
    // pods (alpha free, x = -L/2, y = +/- B/2).
    // For v0.0.0 fix the stern angles at 0 (longitudinal):
    const thr = [_]Thruster{
        .{ .alpha_rad = std.math.pi / 2.0, .x_m = 50.0, .y_m = 0.0 },
        .{ .alpha_rad = 0.0, .x_m = -50.0, .y_m = 10.0 },
        .{ .alpha_rad = 0.0, .x_m = -50.0, .y_m = -10.0 },
    };
    const tau: Demand = .{ .X_n = 10_000.0, .Y_n = 0.0, .N_nm = 0.0 };
    var u: [3]f64 = undefined;
    try allocate(&thr, tau, &u);
    const r = try closingResidual(&thr, &u, tau);
    try std.testing.expect(r < 1.0);
}

test "pure surge demand: bow tunnel inactive, stern pods balance" {
    const thr = [_]Thruster{
        .{ .alpha_rad = std.math.pi / 2.0, .x_m = 50.0, .y_m = 0.0 },
        .{ .alpha_rad = 0.0, .x_m = -50.0, .y_m = 10.0 },
        .{ .alpha_rad = 0.0, .x_m = -50.0, .y_m = -10.0 },
    };
    const tau: Demand = .{ .X_n = 10_000.0, .Y_n = 0.0, .N_nm = 0.0 };
    var u: [3]f64 = undefined;
    try allocate(&thr, tau, &u);
    // Bow tunnel u[0] cannot generate surge -- should be small (zero
    // exactly in the minimum-energy sense for a configuration where
    // the bow tunnel only contributes to Y and N).
    try std.testing.expect(@abs(u[0]) < 1.0);
    // Stern pods each take 5 000 N of surge (symmetric).
    try std.testing.expectApproxEqAbs(u[1], u[2], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f64, 5000.0), u[1], 1.0);
}

test "pure yaw demand: differential stern thrust" {
    const thr = [_]Thruster{
        .{ .alpha_rad = std.math.pi / 2.0, .x_m = 50.0, .y_m = 0.0 },
        .{ .alpha_rad = 0.0, .x_m = -50.0, .y_m = 10.0 },
        .{ .alpha_rad = 0.0, .x_m = -50.0, .y_m = -10.0 },
    };
    const tau: Demand = .{ .X_n = 0.0, .Y_n = 0.0, .N_nm = 50_000.0 };
    var u: [3]f64 = undefined;
    try allocate(&thr, tau, &u);
    // Stern pod 1 at y = +10 contributes -10 (= -y_1) per unit thrust
    // for N; pod 2 at y = -10 contributes +10. So differential
    // (u[2] - u[1]) * 10 = 50000 -> u[2] - u[1] = 5000.
    try std.testing.expectApproxEqAbs(@as(f64, 5000.0), u[2] - u[1], 1.0);
}

test "pure sway demand: bow tunnel + stern azimuth pods produce Y" {
    // Bow tunnel (sway-only) + two stern azimuth pods canted 45 deg
    // outward so the configuration is non-singular (each pod
    // contributes to both X and Y).
    const thr = [_]Thruster{
        .{ .alpha_rad = std.math.pi / 2.0, .x_m = 50.0, .y_m = 0.0 },
        .{ .alpha_rad = std.math.pi / 4.0, .x_m = -50.0, .y_m = 10.0 },
        .{ .alpha_rad = -std.math.pi / 4.0, .x_m = -50.0, .y_m = -10.0 },
    };
    const tau: Demand = .{ .X_n = 0.0, .Y_n = 9000.0, .N_nm = 0.0 };
    var u: [3]f64 = undefined;
    try allocate(&thr, tau, &u);
    const r = try closingResidual(&thr, &u, tau);
    try std.testing.expect(r < 1.0);
}

test "closing residual is small for a well-posed system" {
    const thr = [_]Thruster{
        .{ .alpha_rad = std.math.pi / 2.0, .x_m = 50.0, .y_m = 0.0 },
        .{ .alpha_rad = 0.0, .x_m = -50.0, .y_m = 10.0 },
        .{ .alpha_rad = 0.0, .x_m = -50.0, .y_m = -10.0 },
    };
    const tau: Demand = .{ .X_n = 12_000.0, .Y_n = 4500.0, .N_nm = 35_000.0 };
    var u: [3]f64 = undefined;
    try allocate(&thr, tau, &u);
    const r = try closingResidual(&thr, &u, tau);
    try std.testing.expect(r < 1.0);
}

test "four-thruster redundant configuration (DP-2 style)" {
    // Two bow + two stern azimuth pods.
    const thr = [_]Thruster{
        .{ .alpha_rad = std.math.pi / 2.0, .x_m = 50.0, .y_m = 5.0 },
        .{ .alpha_rad = std.math.pi / 2.0, .x_m = 50.0, .y_m = -5.0 },
        .{ .alpha_rad = 0.0, .x_m = -50.0, .y_m = 10.0 },
        .{ .alpha_rad = 0.0, .x_m = -50.0, .y_m = -10.0 },
    };
    const tau: Demand = .{ .X_n = 10_000.0, .Y_n = 3000.0, .N_nm = 25_000.0 };
    var u: [4]f64 = undefined;
    try allocate(&thr, tau, &u);
    const r = try closingResidual(&thr, &u, tau);
    try std.testing.expect(r < 1.0);
}

test "input rejection: empty thruster list" {
    const thr: []const Thruster = &[_]Thruster{};
    var u: [0]f64 = undefined;
    try std.testing.expectError(
        Error.NonPositiveCount,
        allocate(thr, .{ .X_n = 1, .Y_n = 0, .N_nm = 0 }, &u),
    );
}

test "input rejection: degenerate configuration (all colinear, no yaw)" {
    // Three thrusters all at y = 0 with alpha = 0; cannot produce
    // yaw moment -- B B^T is singular in the N row.
    const thr = [_]Thruster{
        .{ .alpha_rad = 0.0, .x_m = -50.0, .y_m = 0.0 },
        .{ .alpha_rad = 0.0, .x_m = 0.0, .y_m = 0.0 },
        .{ .alpha_rad = 0.0, .x_m = 50.0, .y_m = 0.0 },
    };
    const tau: Demand = .{ .X_n = 1000.0, .Y_n = 0.0, .N_nm = 100.0 };
    var u: [3]f64 = undefined;
    try std.testing.expectError(Error.SingularConfigurationMatrix, allocate(&thr, tau, &u));
}
