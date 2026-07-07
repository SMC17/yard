const std = @import("std");

pub const Error = error{
    SingularMatrix,
};

pub const Complex = struct {
    re: f64,
    im: f64,

    pub fn add(a: Complex, b: Complex) Complex {
        return .{ .re = a.re + b.re, .im = a.im + b.im };
    }
    pub fn sub(a: Complex, b: Complex) Complex {
        return .{ .re = a.re - b.re, .im = a.im - b.im };
    }
    pub fn mul(a: Complex, b: Complex) Complex {
        return .{ .re = a.re * b.re - a.im * b.im, .im = a.re * b.im + a.im * b.re };
    }
    pub fn div(a: Complex, b: Complex) Complex {
        const m = b.re * b.re + b.im * b.im;
        return .{
            .re = (a.re * b.re + a.im * b.im) / m,
            .im = (a.im * b.re - a.re * b.im) / m,
        };
    }
    pub fn abs(a: Complex) f64 {
        return @sqrt(a.re * a.re + a.im * a.im);
    }
};

/// 3x3 real symmetric (or arbitrary) coefficient matrices for the 3-DOF
/// frequency-domain motion equation. All matrices are row-major 3x3.
pub const Matrix3 = [3][3]f64;

/// Forcing 3-vector (complex).
pub const Force3 = [3]Complex;

/// Response 3-vector (complex).
pub const Response3 = [3]Complex;

/// Build the coupled impedance matrix Z(omega) = -(M + A) omega^2 + i B omega + C
/// then solve Z * X = F for complex X via Gauss elimination with partial
/// pivoting on the complex 3x3 system.
pub fn solveRAO(
    M: Matrix3,
    A: Matrix3,
    B: Matrix3,
    C: Matrix3,
    F: Force3,
    omega: f64,
) Error!Response3 {
    var z: [3][3]Complex = undefined;
    var rhs: [3]Complex = F;
    inline for (0..3) |i| {
        inline for (0..3) |j| {
            const meff = M[i][j] + A[i][j];
            z[i][j] = .{
                .re = -meff * omega * omega + C[i][j],
                .im = B[i][j] * omega,
            };
        }
    }
    // Gauss elimination with partial pivoting on complex 3x3.
    inline for (0..3) |k| {
        var pivot_row: usize = k;
        var pivot_mag: f64 = z[k][k].abs();
        inline for (k + 1..3) |r| {
            const m = z[r][k].abs();
            if (m > pivot_mag) {
                pivot_mag = m;
                pivot_row = r;
            }
        }
        if (pivot_mag == 0.0) return Error.SingularMatrix;
        if (pivot_row != k) {
            std.mem.swap([3]Complex, &z[k], &z[pivot_row]);
            std.mem.swap(Complex, &rhs[k], &rhs[pivot_row]);
        }
        inline for (k + 1..3) |r| {
            const factor = z[r][k].div(z[k][k]);
            inline for (k..3) |c| {
                z[r][c] = z[r][c].sub(factor.mul(z[k][c]));
            }
            rhs[r] = rhs[r].sub(factor.mul(rhs[k]));
        }
    }
    var x: [3]Complex = undefined;
    inline for (0..3) |ri| {
        const i = 2 - ri;
        var s = rhs[i];
        inline for (i + 1..3) |j| {
            s = s.sub(z[i][j].mul(x[j]));
        }
        x[i] = s.div(z[i][i]);
    }
    return x;
}

/// Modulus of each DOF (the response-amplitude operator magnitude per DOF).
pub fn raoMagnitudes(x: Response3) [3]f64 {
    return .{ x[0].abs(), x[1].abs(), x[2].abs() };
}

test "complex arithmetic basics" {
    const z1: Complex = .{ .re = 3, .im = 4 };
    const z2: Complex = .{ .re = 1, .im = 2 };
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), z1.abs(), 1e-12);
    const s = z1.add(z2);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), s.re, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), s.im, 1e-12);
    const p = z1.mul(z2);
    try std.testing.expectApproxEqAbs(@as(f64, -5.0), p.re, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), p.im, 1e-12);
}

test "complex division" {
    const a: Complex = .{ .re = 1, .im = 2 };
    const b: Complex = .{ .re = 3, .im = 4 };
    const q = a.div(b);
    // (1+2i)/(3+4i) = (11/25, 2/25)
    try std.testing.expectApproxEqAbs(@as(f64, 11.0 / 25.0), q.re, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0 / 25.0), q.im, 1e-12);
}

test "diagonal system decouples to three 1-DOF RAOs" {
    const M: Matrix3 = .{ .{ 2.0, 0, 0 }, .{ 0, 3.0, 0 }, .{ 0, 0, 4.0 } };
    const A: Matrix3 = .{ .{ 0.5, 0, 0 }, .{ 0, 0.7, 0 }, .{ 0, 0, 0.9 } };
    const Bm: Matrix3 = .{ .{ 0.1, 0, 0 }, .{ 0, 0.2, 0 }, .{ 0, 0, 0.3 } };
    const C: Matrix3 = .{ .{ 5.0, 0, 0 }, .{ 0, 8.0, 0 }, .{ 0, 0, 11.0 } };
    const F: Force3 = .{
        .{ .re = 1, .im = 0 },
        .{ .re = 0, .im = 2 },
        .{ .re = 3, .im = 4 },
    };
    const omega = 1.5;
    const x = try solveRAO(M, A, Bm, C, F, omega);
    // Independent 1-DOF: x_i = F_i / (-(M_i+A_i)omega^2 + i B_i omega + C_i)
    inline for (0..3) |i| {
        const m_eff = M[i][i] + A[i][i];
        const denom: Complex = .{
            .re = -m_eff * omega * omega + C[i][i],
            .im = Bm[i][i] * omega,
        };
        const expected = F[i].div(denom);
        try std.testing.expectApproxEqAbs(expected.re, x[i].re, 1e-10);
        try std.testing.expectApproxEqAbs(expected.im, x[i].im, 1e-10);
    }
}

test "identity Z gives X = F" {
    const M: Matrix3 = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
    const A: Matrix3 = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
    const Bm: Matrix3 = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
    const C: Matrix3 = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
    const F: Force3 = .{
        .{ .re = 7, .im = -3 },
        .{ .re = 2, .im = 5 },
        .{ .re = -1, .im = 1 },
    };
    const x = try solveRAO(M, A, Bm, C, F, 0.0);
    inline for (0..3) |i| {
        try std.testing.expectApproxEqAbs(F[i].re, x[i].re, 1e-12);
        try std.testing.expectApproxEqAbs(F[i].im, x[i].im, 1e-12);
    }
}

test "raoMagnitudes computes per-DOF modulus" {
    const x: Response3 = .{
        .{ .re = 3, .im = 4 },
        .{ .re = 0, .im = 5 },
        .{ .re = -8, .im = 6 },
    };
    const mags = raoMagnitudes(x);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), mags[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), mags[1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), mags[2], 1e-12);
}

test "coupled system: off-diagonal restoring rotates response" {
    // Test that with off-diagonal coupling, the response is not the same
    // as the diagonal-only case.
    const M: Matrix3 = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
    const A: Matrix3 = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
    const Bm: Matrix3 = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
    const C_diag: Matrix3 = .{ .{ 10, 0, 0 }, .{ 0, 10, 0 }, .{ 0, 0, 10 } };
    const C_coupled: Matrix3 = .{ .{ 10, 2, 0 }, .{ 2, 10, 0 }, .{ 0, 0, 10 } };
    const F: Force3 = .{
        .{ .re = 1, .im = 0 },
        .{ .re = 0, .im = 0 },
        .{ .re = 0, .im = 0 },
    };
    const x_d = try solveRAO(M, A, Bm, C_diag, F, 0.0);
    const x_c = try solveRAO(M, A, Bm, C_coupled, F, 0.0);
    // Diagonal: x = (1/10, 0, 0).
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), x_d[0].re, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), x_d[1].re, 1e-12);
    // Coupled: heave forcing induces a nonzero pitch response.
    try std.testing.expect(@abs(x_c[1].re) > 1e-6);
    // And modifies heave amplitude.
    try std.testing.expect(@abs(x_c[0].re - 0.1) > 1e-6);
}

test "singular matrix detected" {
    const M: Matrix3 = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
    const A: Matrix3 = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
    const Bm: Matrix3 = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
    // Set C so that the impedance is identically zero at omega=1 in DOF 0:
    // -(1+0) * 1 + 1 = 0, with zero damping and zero coupling.
    const C: Matrix3 = .{ .{ 1, 0, 0 }, .{ 0, 2, 0 }, .{ 0, 0, 2 } };
    const F: Force3 = .{
        .{ .re = 1, .im = 0 },
        .{ .re = 0, .im = 0 },
        .{ .re = 0, .im = 0 },
    };
    try std.testing.expectError(Error.SingularMatrix, solveRAO(M, A, Bm, C, F, 1.0));
}

test "resonance peak in 1-DOF embedded slot" {
    const M: Matrix3 = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
    const A: Matrix3 = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
    const Bm: Matrix3 = .{ .{ 0.01, 0, 0 }, .{ 0, 0.01, 0 }, .{ 0, 0, 0.01 } };
    const C: Matrix3 = .{ .{ 100, 0, 0 }, .{ 0, 100, 0 }, .{ 0, 0, 100 } };
    const F: Force3 = .{
        .{ .re = 1, .im = 0 },
        .{ .re = 0, .im = 0 },
        .{ .re = 0, .im = 0 },
    };
    const omega_n = @sqrt(100.0 / 1.0);
    const x_off = try solveRAO(M, A, Bm, C, F, 0.5 * omega_n);
    const x_on = try solveRAO(M, A, Bm, C, F, omega_n);
    // At resonance, response peaks; off resonance, response is smaller.
    try std.testing.expect(x_on[0].abs() > x_off[0].abs() * 10.0);
}

test "low-frequency limit gives quasi-static response x = C^-1 F" {
    const M: Matrix3 = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
    const A: Matrix3 = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
    const Bm: Matrix3 = .{ .{ 0.1, 0, 0 }, .{ 0, 0.1, 0 }, .{ 0, 0, 0.1 } };
    const C: Matrix3 = .{ .{ 4, 1, 0 }, .{ 1, 5, 0 }, .{ 0, 0, 6 } };
    const F: Force3 = .{
        .{ .re = 2, .im = 0 },
        .{ .re = 1, .im = 0 },
        .{ .re = 3, .im = 0 },
    };
    const x = try solveRAO(M, A, Bm, C, F, 1e-8);
    // C^-1 F for the 2x2 block: det = 20-1 = 19. inv = (1/19) * [[5,-1],[-1,4]]
    // x1 = (5*2 - 1*1)/19 = 9/19, x2 = (-1*2 + 4*1)/19 = 2/19, x3 = 3/6 = 0.5
    try std.testing.expectApproxEqAbs(@as(f64, 9.0 / 19.0), x[0].re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0 / 19.0), x[1].re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), x[2].re, 1e-6);
}

test "high-frequency limit: response goes to zero" {
    const M: Matrix3 = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
    const A: Matrix3 = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
    const Bm: Matrix3 = .{ .{ 0.1, 0, 0 }, .{ 0, 0.1, 0 }, .{ 0, 0, 0.1 } };
    const C: Matrix3 = .{ .{ 10, 0, 0 }, .{ 0, 10, 0 }, .{ 0, 0, 10 } };
    const F: Force3 = .{
        .{ .re = 1, .im = 0 },
        .{ .re = 1, .im = 0 },
        .{ .re = 1, .im = 0 },
    };
    const x = try solveRAO(M, A, Bm, C, F, 100.0);
    try std.testing.expect(x[0].abs() < 1e-3);
    try std.testing.expect(x[1].abs() < 1e-3);
    try std.testing.expect(x[2].abs() < 1e-3);
}

test "force in DOF 2 only does not excite DOF 0 if uncoupled in C" {
    const M: Matrix3 = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
    const A: Matrix3 = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
    const Bm: Matrix3 = .{ .{ 0.1, 0, 0 }, .{ 0, 0.1, 0 }, .{ 0, 0, 0.1 } };
    const C: Matrix3 = .{ .{ 5, 0, 0 }, .{ 0, 0.0, 0.3 }, .{ 0, 0.3, 5 } };
    const F: Force3 = .{
        .{ .re = 0, .im = 0 },
        .{ .re = 0, .im = 0 },
        .{ .re = 1, .im = 0 },
    };
    const x = try solveRAO(M, A, Bm, C, F, 0.5);
    try std.testing.expect(x[0].abs() < 1e-10);
}
