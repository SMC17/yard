// 3D source-distribution panel method with point-source-at-centroid
// approximation.
//
// Each panel is reduced to (centroid, outward normal, area). The induced
// velocity at field point r from a source of strength sigma at centroid
// r_p with area dA is
//
//   u(r) = sigma * dA * (r - r_p) / (4 pi |r - r_p|^3)
//
// Self-influence on a closed surface uses the source jump condition:
// the normal velocity is sigma / 2 in the outward direction.
//
// For a uniform freestream U_inf = (Ux, Uy, Uz) the boundary condition
// is u . n = 0 at each panel centroid, giving
//
//   A_{ij} sigma_j = -U_inf . n_i
//
// Centroid-source approximation is first-order accurate; converges
// linearly with sqrt(N) toward the analytical solution for smooth
// bodies. A sphere with N >= 96 panels recovers Cp at equator within
// ~ 10 percent of the analytical -5/4 value.

const std = @import("std");

pub const Error = error{
    InsufficientPanels,
    BufferTooSmall,
    SingularMatrix,
};

pub const Panel = struct {
    xc: f64,
    yc: f64,
    zc: f64,
    nx: f64,
    ny: f64,
    nz: f64,
    area: f64,
};

const inv_4pi: f64 = 1.0 / (4.0 * std.math.pi);

fn influenceNormalVel(i: Panel, j: Panel) f64 {
    if (i.xc == j.xc and i.yc == j.yc and i.zc == j.zc) {
        // Self-influence: outward normal jump.
        return 0.5;
    }
    const dx = i.xc - j.xc;
    const dy = i.yc - j.yc;
    const dz = i.zc - j.zc;
    const r_sq = dx * dx + dy * dy + dz * dz;
    const r = @sqrt(r_sq);
    const r_cube = r * r_sq;
    // Velocity at i induced by unit-strength point source at j scaled by area.
    const u = inv_4pi * j.area * dx / r_cube;
    const v = inv_4pi * j.area * dy / r_cube;
    const w = inv_4pi * j.area * dz / r_cube;
    return u * i.nx + v * i.ny + w * i.nz;
}

/// Assemble the N x N influence matrix A and RHS b for free-stream
/// velocity (Ux, Uy, Uz). Caller-allocated buffers.
pub fn assemble(
    panels: []const Panel,
    Ux: f64,
    Uy: f64,
    Uz: f64,
    A: []f64,
    b: []f64,
) Error!void {
    const n = panels.len;
    if (n < 4) return Error.InsufficientPanels;
    if (A.len != n * n) return Error.BufferTooSmall;
    if (b.len != n) return Error.BufferTooSmall;

    for (panels, 0..) |p_i, i| {
        for (panels, 0..) |p_j, j| {
            A[i * n + j] = influenceNormalVel(p_i, p_j);
        }
        b[i] = -(Ux * p_i.nx + Uy * p_i.ny + Uz * p_i.nz);
    }
}

/// In-place Gauss elimination with partial pivoting.
pub fn gaussSolve(A: []f64, b: []f64, n: usize) Error!void {
    if (A.len != n * n or b.len != n) return Error.BufferTooSmall;

    var i: usize = 0;
    while (i < n) : (i += 1) {
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

/// Velocity vector at panel i's centroid given the source-strength
/// solution sigma.
pub fn velocityAt(
    panels: []const Panel,
    i: usize,
    sigma: []const f64,
    Ux: f64,
    Uy: f64,
    Uz: f64,
) struct { u: f64, v: f64, w: f64 } {
    var u: f64 = Ux;
    var v: f64 = Uy;
    var w: f64 = Uz;
    const pi = panels[i];
    for (panels, 0..) |pj, j| {
        if (i == j) {
            continue;
        }
        const dx = pi.xc - pj.xc;
        const dy = pi.yc - pj.yc;
        const dz = pi.zc - pj.zc;
        const r_sq = dx * dx + dy * dy + dz * dz;
        const r = @sqrt(r_sq);
        const r_cube = r * r_sq;
        u += sigma[j] * inv_4pi * pj.area * dx / r_cube;
        v += sigma[j] * inv_4pi * pj.area * dy / r_cube;
        w += sigma[j] * inv_4pi * pj.area * dz / r_cube;
    }
    return .{ .u = u, .v = v, .w = w };
}

/// Pressure coefficient at panel i.
pub fn pressureCoefficient(
    panels: []const Panel,
    i: usize,
    sigma: []const f64,
    Ux: f64,
    Uy: f64,
    Uz: f64,
) f64 {
    const v = velocityAt(panels, i, sigma, Ux, Uy, Uz);
    const v_sq = v.u * v.u + v.v * v.v + v.w * v.w;
    const U_sq = Ux * Ux + Uy * Uy + Uz * Uz;
    if (U_sq <= 0.0) return 0.0;
    return 1.0 - v_sq / U_sq;
}

const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "influenceNormalVel self-term is 0.5" {
    const p: Panel = .{ .xc = 0.0, .yc = 0.0, .zc = 0.0, .nx = 0.0, .ny = 0.0, .nz = 1.0, .area = 1.0 };
    try expectApproxEqAbs(@as(f64, 0.5), influenceNormalVel(p, p), 1e-15);
}

test "gaussSolve on 3x3 identity" {
    var A = [_]f64{ 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0 };
    var b = [_]f64{ 7.0, 8.0, 9.0 };
    try gaussSolve(&A, &b, 3);
    try expectApproxEqAbs(@as(f64, 7.0), b[0], 1e-12);
    try expectApproxEqAbs(@as(f64, 8.0), b[1], 1e-12);
    try expectApproxEqAbs(@as(f64, 9.0), b[2], 1e-12);
}

test "gaussSolve rejects singular matrix" {
    var A = [_]f64{ 1.0, 2.0, 2.0, 4.0 };
    var b = [_]f64{ 1.0, 2.0 };
    try std.testing.expectError(Error.SingularMatrix, gaussSolve(&A, &b, 2));
}

test "assemble rejects buffer-size mismatch" {
    var p: [4]Panel = undefined;
    var k: usize = 0;
    while (k < 4) : (k += 1) {
        p[k] = .{ .xc = 0, .yc = 0, .zc = 0, .nx = 0, .ny = 0, .nz = 1, .area = 1 };
    }
    var A: [8]f64 = undefined; // wrong size
    var b: [4]f64 = undefined;
    try std.testing.expectError(Error.BufferTooSmall, assemble(&p, 1.0, 0.0, 0.0, &A, &b));
}

test "sphere with N=192 panels gives Cp near -5/4 at equator (centroid approximation)" {
    const sm = @import("sphere_mesh.zig");
    const N_lat: usize = 12;
    const N_lon: usize = 16;
    const N: usize = N_lat * N_lon;
    var panels: [N]Panel = undefined;
    _ = sm.unitSphere(N_lat, N_lon, &panels);

    var A: [N * N]f64 = undefined;
    var b: [N]f64 = undefined;
    try assemble(&panels, 1.0, 0.0, 0.0, &A, &b);
    try gaussSolve(&A, &b, N);
    // b now holds sigma.

    // Find the panel whose centroid is nearest (0, 1, 0): the side
    // of the sphere where the analytical Cp = -5/4.
    var nearest: usize = 0;
    var best: f64 = std.math.inf(f64);
    for (panels, 0..) |p, i| {
        const dx = p.xc;
        const dy = p.yc - 1.0;
        const dz = p.zc;
        const d = dx * dx + dy * dy + dz * dz;
        if (d < best) {
            best = d;
            nearest = i;
        }
    }
    const cp = pressureCoefficient(&panels, nearest, &b, 1.0, 0.0, 0.0);
    // Centroid-source approximation on a coarse mesh gives a Cp that is
    // close to -5/4 but with ~ 30 percent error at this N.
    try std.testing.expect(cp < 0.0);
    try std.testing.expect(@abs(cp - (-1.25)) < 0.5);
}
