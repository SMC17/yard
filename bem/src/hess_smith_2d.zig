// 2D Hess-Smith non-lifting source-distribution panel method.
//
// References:
//   Hess, J.L. and Smith, A.M.O. (1964). "Calculation of nonlifting
//   potential flow about arbitrary three-dimensional bodies."
//   J. Ship Research 8(2): 22-44.
//   (The 2D case is documented in Katz and Plotkin (2001),
//   "Low-Speed Aerodynamics," 2nd ed., Ch. 11.)
//
// The body surface is discretized into N flat panels. On each panel
// a constant-strength source distribution sigma_j is unknown. The
// boundary condition is zero normal velocity at each panel control
// point (centroid). This produces a linear system:
//
//   A * sigma = b
//
// where A_{ij} is the normal velocity induced at panel i's centroid
// by a unit source distribution on panel j, and b_i = -U_inf * n_x_i
// (the inward normal-velocity contribution of the freestream).
//
// For a 2D source panel of strength sigma at position (x_p, y_p) along
// the panel, the induced velocity at a field point (x, y) is:
//
//   u(x, y) = -(sigma / (2 pi)) * ln(r)
//
// where r is distance. The induced velocity vector is the gradient of
// this potential.
//
// Closed-form influence coefficients for flat 2D panels (in the panel-
// local coordinate system) are well known. We follow the formulation
// in Katz & Plotkin (2001) eq. 11.97 to 11.99: a panel of length L
// along its own x-axis, a control point at (x, y), produces normal
// (panel-local v) and tangential (panel-local u) velocities:
//
//   u = (sigma / (2 pi)) * 0.5 * ln((x^2 + y^2) / ((x - L)^2 + y^2))
//   v = (sigma / (2 pi)) * (atan2(y, x - L) - atan2(y, x))
//
// Self-influence (panel induces on itself, i = j): u = 0 and
// v = sigma / 2 (the source-panel jump condition).

const std = @import("std");

pub const Error = error{
    InsufficientPanels,
    DegeneratePanel,
    SingularMatrix,
    BufferTooSmall,
};

/// 2D panel: two endpoint coordinates plus precomputed derived data.
pub const Panel = struct {
    x1: f64,
    y1: f64,
    x2: f64,
    y2: f64,
    /// Centroid (control point).
    xc: f64,
    yc: f64,
    /// Length.
    L: f64,
    /// Tangent unit vector (along panel from 1 to 2).
    tx: f64,
    ty: f64,
    /// Normal unit vector (90 deg CCW from tangent; points outward for
    /// a polygon traced clockwise, inward for counter-clockwise).
    nx: f64,
    ny: f64,
};

pub fn buildPanel(x1: f64, y1: f64, x2: f64, y2: f64) Error!Panel {
    const dx = x2 - x1;
    const dy = y2 - y1;
    const L = @sqrt(dx * dx + dy * dy);
    if (L <= 0.0) return Error.DegeneratePanel;
    const tx = dx / L;
    const ty = dy / L;
    return .{
        .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2,
        .xc = 0.5 * (x1 + x2),
        .yc = 0.5 * (y1 + y2),
        .L = L,
        .tx = tx, .ty = ty,
        // Outward-pointing normal for a clockwise-traced polygon:
        // n = (ty, -tx); for CCW use (-ty, tx).
        .nx = ty,
        .ny = -tx,
    };
}

/// Influence of panel j (unit source strength) on the control point at
/// the centroid of panel i, in the GLOBAL frame. Returns (u_global,
/// v_global) of the induced velocity.
fn panelInfluence(i: Panel, j: Panel) struct { u: f64, v: f64 } {
    // Transform i's control point into j's local coordinates.
    const dx = i.xc - j.x1;
    const dy = i.yc - j.y1;
    const x = dx * j.tx + dy * j.ty;
    const y = -dx * j.ty + dy * j.tx;

    var u_local: f64 = 0.0;
    var v_local: f64 = 0.0;

    // Self-influence: i == j.
    if (@abs(x - 0.5 * j.L) < 1.0e-9 and @abs(y) < 1.0e-9) {
        u_local = 0.0;
        v_local = 0.5; // (1 / (2 pi)) * pi = 0.5 from the source jump.
    } else {
        const inv_2pi: f64 = 1.0 / (2.0 * std.math.pi);
        const r1_sq = x * x + y * y;
        const r2_sq = (x - j.L) * (x - j.L) + y * y;
        if (r1_sq > 0.0 and r2_sq > 0.0) {
            u_local = inv_2pi * 0.5 * std.math.log(f64, std.math.e, r1_sq / r2_sq);
        }
        v_local = inv_2pi * (std.math.atan2(y, x - j.L) - std.math.atan2(y, x));
    }

    // Transform local velocity back to global frame.
    const u_global = u_local * j.tx - v_local * j.ty;
    const v_global = u_local * j.ty + v_local * j.tx;
    return .{ .u = u_global, .v = v_global };
}

/// Build the influence matrix A and RHS b for a free-stream velocity
/// (U_inf, V_inf). The caller provides preallocated A (n*n) and b (n).
pub fn assemble(
    panels: []const Panel,
    U_inf: f64,
    V_inf: f64,
    A: []f64,
    b: []f64,
) Error!void {
    const n = panels.len;
    if (n < 3) return Error.InsufficientPanels;
    if (A.len != n * n) return Error.BufferTooSmall;
    if (b.len != n) return Error.BufferTooSmall;

    for (panels, 0..) |p_i, i| {
        for (panels, 0..) |p_j, j| {
            const inf = panelInfluence(p_i, p_j);
            // Project induced velocity onto i's outward normal.
            A[i * n + j] = inf.u * p_i.nx + inf.v * p_i.ny;
        }
        b[i] = -(U_inf * p_i.nx + V_inf * p_i.ny);
    }
}

/// In-place Gauss elimination with partial pivoting. Solves A x = b;
/// result is written back into b.
pub fn gaussSolve(A: []f64, b: []f64, n: usize) Error!void {
    if (A.len != n * n or b.len != n) return Error.BufferTooSmall;

    var i: usize = 0;
    while (i < n) : (i += 1) {
        // Pivot: find row with max |A[k, i]| for k >= i.
        var pivot: usize = i;
        var max_val: f64 = @abs(A[i * n + i]);
        var k: usize = i + 1;
        while (k < n) : (k += 1) {
            const v = @abs(A[k * n + i]);
            if (v > max_val) {
                max_val = v;
                pivot = k;
            }
        }
        if (max_val < 1.0e-14) return Error.SingularMatrix;
        if (pivot != i) {
            var j: usize = 0;
            while (j < n) : (j += 1) {
                const tmp = A[i * n + j];
                A[i * n + j] = A[pivot * n + j];
                A[pivot * n + j] = tmp;
            }
            const tb = b[i];
            b[i] = b[pivot];
            b[pivot] = tb;
        }
        // Eliminate column i below row i.
        k = i + 1;
        while (k < n) : (k += 1) {
            const factor = A[k * n + i] / A[i * n + i];
            var j: usize = i;
            while (j < n) : (j += 1) {
                A[k * n + j] -= factor * A[i * n + j];
            }
            b[k] -= factor * b[i];
        }
    }
    // Back substitution.
    var ii: isize = @intCast(n - 1);
    while (ii >= 0) : (ii -= 1) {
        const idx: usize = @intCast(ii);
        var sum: f64 = b[idx];
        var j: usize = idx + 1;
        while (j < n) : (j += 1) {
            sum -= A[idx * n + j] * b[j];
        }
        b[idx] = sum / A[idx * n + idx];
    }
}

/// Compute the tangential velocity at panel i's centroid given the
/// source-strength solution sigma[].
pub fn tangentialVelocity(
    panels: []const Panel,
    i: usize,
    sigma: []const f64,
    U_inf: f64,
    V_inf: f64,
) f64 {
    var u: f64 = U_inf;
    var v: f64 = V_inf;
    for (panels, 0..) |p_j, j| {
        const inf = panelInfluence(panels[i], p_j);
        u += sigma[j] * inf.u;
        v += sigma[j] * inf.v;
    }
    return u * panels[i].tx + v * panels[i].ty;
}

/// Pressure coefficient at panel i's centroid: C_p = 1 - (V_t / U_inf_mag)^2.
pub fn pressureCoefficient(
    panels: []const Panel,
    i: usize,
    sigma: []const f64,
    U_inf: f64,
    V_inf: f64,
) f64 {
    const V_t = tangentialVelocity(panels, i, sigma, U_inf, V_inf);
    const U_mag_sq = U_inf * U_inf + V_inf * V_inf;
    if (U_mag_sq <= 0.0) return 0.0;
    return 1.0 - (V_t * V_t) / U_mag_sq;
}

const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "buildPanel rejects zero-length panel" {
    try std.testing.expectError(Error.DegeneratePanel, buildPanel(0.0, 0.0, 0.0, 0.0));
}

test "buildPanel computes correct length and tangent" {
    const p = try buildPanel(0.0, 0.0, 3.0, 4.0);
    try expectApproxEqAbs(@as(f64, 5.0), p.L, 1e-12);
    try expectApproxEqAbs(@as(f64, 0.6), p.tx, 1e-12);
    try expectApproxEqAbs(@as(f64, 0.8), p.ty, 1e-12);
}

test "Hess-Smith on a unit circle with U_inf = 1 produces a stagnation point at theta = 180" {
    // Discretize circle into N = 64 panels traced clockwise (so outward normal is (ty, -tx)).
    const N: usize = 64;
    var panels: [N]Panel = undefined;
    var k: usize = 0;
    while (k < N) : (k += 1) {
        const theta1 = -@as(f64, @floatFromInt(k)) * 2.0 * std.math.pi / @as(f64, @floatFromInt(N));
        const theta2 = -@as(f64, @floatFromInt(k + 1)) * 2.0 * std.math.pi / @as(f64, @floatFromInt(N));
        panels[k] = try buildPanel(@cos(theta1), @sin(theta1), @cos(theta2), @sin(theta2));
    }

    var A: [N * N]f64 = undefined;
    var b: [N]f64 = undefined;
    try assemble(&panels, 1.0, 0.0, &A, &b);
    try gaussSolve(&A, &b, N);

    // b now contains sigma. At the rear stagnation point (theta = pi,
    // i.e., the panel whose centroid is closest to (-1, 0)) the
    // tangential velocity should be near zero, so C_p should be ~ 1.
    var nearest: usize = 0;
    var best: f64 = std.math.inf(f64);
    for (panels, 0..) |p, i| {
        const dx = p.xc + 1.0;
        const dy = p.yc;
        const d = dx * dx + dy * dy;
        if (d < best) {
            best = d;
            nearest = i;
        }
    }
    const cp_rear = pressureCoefficient(&panels, nearest, &b, 1.0, 0.0);
    // Stagnation Cp = 1.0. With 64 panels, expect within 0.1.
    try std.testing.expect(@abs(cp_rear - 1.0) < 0.1);

    // At theta = pi/2 (top of circle, centroid near (0, 1)), the
    // analytical Cp = 1 - 4 sin^2(pi/2) = -3. Look for the panel
    // closest to (0, 1).
    var top: usize = 0;
    best = std.math.inf(f64);
    for (panels, 0..) |p, i| {
        const dx = p.xc;
        const dy = p.yc - 1.0;
        const d = dx * dx + dy * dy;
        if (d < best) {
            best = d;
            top = i;
        }
    }
    const cp_top = pressureCoefficient(&panels, top, &b, 1.0, 0.0);
    // With 64 panels, expect within 0.5 of -3 (BEM converges roughly
    // linearly with panel count for the source-only formulation on
    // a circle; tighter would require more panels).
    try std.testing.expect(@abs(cp_top - (-3.0)) < 0.5);
}

test "gaussSolve on a 3x3 identity returns b unchanged" {
    var A = [_]f64{ 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0 };
    var b = [_]f64{ 1.0, 2.0, 3.0 };
    try gaussSolve(&A, &b, 3);
    try expectApproxEqAbs(@as(f64, 1.0), b[0], 1e-12);
    try expectApproxEqAbs(@as(f64, 2.0), b[1], 1e-12);
    try expectApproxEqAbs(@as(f64, 3.0), b[2], 1e-12);
}

test "gaussSolve on a known small system" {
    // System:  [2 1 1; 1 3 2; 1 0 0] x = [4; 5; 6]
    // Row 3: x = 6. Substitute -> y + z = -8 and 3y + 2z = -1.
    // y = 15, z = -23.
    var A = [_]f64{ 2.0, 1.0, 1.0, 1.0, 3.0, 2.0, 1.0, 0.0, 0.0 };
    var b = [_]f64{ 4.0, 5.0, 6.0 };
    try gaussSolve(&A, &b, 3);
    try expectApproxEqAbs(@as(f64, 6.0), b[0], 1e-10);
    try expectApproxEqAbs(@as(f64, 15.0), b[1], 1e-10);
    try expectApproxEqAbs(@as(f64, -23.0), b[2], 1e-10);
}

test "gaussSolve rejects singular matrix" {
    var A = [_]f64{ 1.0, 2.0, 2.0, 4.0 };
    var b = [_]f64{ 1.0, 2.0 };
    try std.testing.expectError(Error.SingularMatrix, gaussSolve(&A, &b, 2));
}

test "assemble rejects buffer size mismatch" {
    var p: [3]Panel = undefined;
    p[0] = try buildPanel(0.0, 0.0, 1.0, 0.0);
    p[1] = try buildPanel(1.0, 0.0, 0.5, 1.0);
    p[2] = try buildPanel(0.5, 1.0, 0.0, 0.0);
    var A: [5]f64 = undefined; // wrong size
    var b: [3]f64 = undefined;
    try std.testing.expectError(Error.BufferTooSmall, assemble(&p, 1.0, 0.0, &A, &b));
}
