const std = @import("std");

pub const Error = error{
    InsufficientPoints,
    UnequalLength,
    NonUniformSpacing,
    OmegaNotSorted,
};

/// Simpson 1/3 integral on uniform spacing of an arbitrary integrand
/// `f`. Uses 3/8 closure on the trailing pair when N is even (so the
/// number of intervals is odd). `f.len` must be at least 4.
pub fn simpsonUniform(f: []const f64, h: f64) Error!f64 {
    const n = f.len;
    if (n < 4) return Error.InsufficientPoints;
    if (h <= 0.0) return Error.NonUniformSpacing;
    // Decide whether the number of intervals is even (1/3 applies whole)
    // or odd (use 1/3 on the first n-4 intervals and 3/8 on the last 3).
    const intervals = n - 1;
    const use_3_8_tail = (intervals % 2) != 0;
    var sum: f64 = 0.0;
    const last_for_13: usize = if (use_3_8_tail) n - 4 else n - 1;
    // Simpson 1/3 from index 0 to index last_for_13.
    if (last_for_13 >= 2) {
        sum += f[0] + f[last_for_13];
        var i: usize = 1;
        while (i < last_for_13) : (i += 1) {
            if (i % 2 == 1) {
                sum += 4.0 * f[i];
            } else {
                sum += 2.0 * f[i];
            }
        }
        sum *= h / 3.0;
    }
    if (use_3_8_tail) {
        const a = f[n - 4];
        const b = f[n - 3];
        const c = f[n - 2];
        const d = f[n - 1];
        sum += (3.0 * h / 8.0) * (a + 3.0 * b + 3.0 * c + d);
    }
    return sum;
}

/// n-th spectral moment of an arbitrary spectrum `S(omega)` sampled on
/// uniform `omega` ordinates. m_n = integrate omega^n S(omega) dw.
pub fn spectralMoment(n: u32, omega: []const f64, S: []const f64) Error!f64 {
    if (omega.len != S.len) return Error.UnequalLength;
    if (omega.len < 4) return Error.InsufficientPoints;
    var i: usize = 1;
    while (i < omega.len) : (i += 1) {
        if (!(omega[i] > omega[i - 1])) return Error.OmegaNotSorted;
    }
    const h = omega[1] - omega[0];
    const tol = 1e-9 * @max(@abs(h), 1.0);
    var k: usize = 1;
    while (k < omega.len - 1) : (k += 1) {
        const dh = (omega[k + 1] - omega[k]) - h;
        if (@abs(dh) > tol) return Error.NonUniformSpacing;
    }
    // Build integrand omega^n * S(omega) in a fixed-size stack array up
    // to N=4096. For larger arrays the caller can integrate in
    // segments; this is an allocator-free kernel.
    var buf: [4096]f64 = undefined;
    if (omega.len > buf.len) return Error.InsufficientPoints;
    var idx: usize = 0;
    while (idx < omega.len) : (idx += 1) {
        var w_pow: f64 = 1.0;
        var p: u32 = 0;
        while (p < n) : (p += 1) w_pow *= omega[idx];
        buf[idx] = w_pow * S[idx];
    }
    return try simpsonUniform(buf[0..omega.len], h);
}

/// Significant response amplitude derived from m_0 of the response
/// spectrum. H_s_R = 4 sqrt(m_0) per Rayleigh narrow-band.
pub fn significantResponseAmplitude(m0_response: f64) f64 {
    return 4.0 * @sqrt(m0_response);
}

/// Build the response spectrum S_R(omega) = |H(omega)|^2 * S(omega)
/// into the caller's `out` buffer.
pub fn responseSpectrum(H_mag_sq: []const f64, S_wave: []const f64, out: []f64) Error!void {
    if (H_mag_sq.len != S_wave.len) return Error.UnequalLength;
    if (out.len != S_wave.len) return Error.UnequalLength;
    var i: usize = 0;
    while (i < S_wave.len) : (i += 1) {
        out[i] = H_mag_sq[i] * S_wave[i];
    }
}

/// Mean zero-up-crossing period from m_0 and m_2 of the response
/// spectrum. T_z = 2 pi sqrt(m_0 / m_2).
pub fn meanZeroCrossingPeriod(m0: f64, m2: f64) f64 {
    return 2.0 * std.math.pi * @sqrt(m0 / m2);
}

test "Simpson 1/3 on x^2 over [0, 1]" {
    // Exact integral = 1/3.
    const n: usize = 11;
    var f: [n]f64 = undefined;
    const h: f64 = 1.0 / @as(f64, @floatFromInt(n - 1));
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const x = @as(f64, @floatFromInt(i)) * h;
        f[i] = x * x;
    }
    const got = try simpsonUniform(&f, h);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), got, 1e-12);
}

test "Simpson 3/8 tail kicks in on even N=12" {
    // N=12 -> 11 intervals (odd) -> 3/8 applied to last 3.
    // Use x^3 over [0, 1], exact = 1/4.
    const n: usize = 12;
    var f: [n]f64 = undefined;
    const h: f64 = 1.0 / @as(f64, @floatFromInt(n - 1));
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const x = @as(f64, @floatFromInt(i)) * h;
        f[i] = x * x * x;
    }
    const got = try simpsonUniform(&f, h);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), got, 1e-12);
}

test "spectralMoment m0 of a unit rectangle equals area" {
    var omega: [21]f64 = undefined;
    var S: [21]f64 = undefined;
    var i: usize = 0;
    while (i < omega.len) : (i += 1) {
        omega[i] = 1.0 + 0.1 * @as(f64, @floatFromInt(i));
        S[i] = 2.0;
    }
    const m0 = try spectralMoment(0, &omega, &S);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), m0, 1e-12);
}

test "spectralMoment m1 of constant S gives w_max^2 - w_min^2 over 2" {
    var omega: [21]f64 = undefined;
    var S: [21]f64 = undefined;
    var i: usize = 0;
    while (i < omega.len) : (i += 1) {
        omega[i] = 1.0 + 0.1 * @as(f64, @floatFromInt(i));
        S[i] = 1.0;
    }
    const m1 = try spectralMoment(1, &omega, &S);
    // integrate omega from 1 to 3 = (9-1)/2 = 4
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), m1, 1e-12);
}

test "responseSpectrum multiplies element-wise" {
    const H: [5]f64 = .{ 0.5, 1.0, 1.5, 2.0, 2.5 };
    const S: [5]f64 = .{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    var out: [5]f64 = undefined;
    try responseSpectrum(&H, &S, &out);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), out[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), out[1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 4.5), out[2], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), out[3], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 12.5), out[4], 1e-12);
}

test "significantResponseAmplitude from m0" {
    const m0: f64 = 1.5625;
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), significantResponseAmplitude(m0), 1e-12);
}

test "H_s of S identically 1 over [1, 3] is 4 sqrt(2)" {
    // m_0 = integrate 1 dw over [1, 3] = 2. H_s = 4 sqrt(2).
    var omega: [21]f64 = undefined;
    var S: [21]f64 = undefined;
    var i: usize = 0;
    while (i < omega.len) : (i += 1) {
        omega[i] = 1.0 + 0.1 * @as(f64, @floatFromInt(i));
        S[i] = 1.0;
    }
    const m0 = try spectralMoment(0, &omega, &S);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), m0, 1e-12);
    const Hs = significantResponseAmplitude(m0);
    try std.testing.expectApproxEqAbs(4.0 * @sqrt(2.0), Hs, 1e-12);
}

test "white-noise H = 1 reproduces wave m_0 = response m_0" {
    // S(omega) = 0.5 + 0.5 cos(omega), |H|^2 = 1 -> response m_0 = wave m_0.
    var omega: [41]f64 = undefined;
    var S: [41]f64 = undefined;
    var H_sq: [41]f64 = undefined;
    var i: usize = 0;
    while (i < omega.len) : (i += 1) {
        omega[i] = 0.5 + 0.05 * @as(f64, @floatFromInt(i));
        S[i] = 0.5 + 0.5 * @cos(omega[i]);
        H_sq[i] = 1.0;
    }
    const m0_wave = try spectralMoment(0, &omega, &S);
    var SR: [41]f64 = undefined;
    try responseSpectrum(&H_sq, &S, &SR);
    const m0_resp = try spectralMoment(0, &omega, &SR);
    try std.testing.expectApproxEqAbs(m0_wave, m0_resp, 1e-12);
}

test "meanZeroCrossingPeriod matches closed form" {
    const m0: f64 = 2.0;
    const m2: f64 = 0.5;
    const Tz = meanZeroCrossingPeriod(m0, m2);
    const expected = 2.0 * std.math.pi * @sqrt(4.0);
    try std.testing.expectApproxEqAbs(expected, Tz, 1e-12);
}

test "unequal-length input rejected" {
    const omega: [5]f64 = .{ 1, 2, 3, 4, 5 };
    const S: [4]f64 = .{ 1, 2, 3, 4 };
    try std.testing.expectError(Error.UnequalLength, spectralMoment(0, &omega, &S));
}

test "non-uniform spacing rejected" {
    const omega: [5]f64 = .{ 1.0, 1.1, 1.25, 1.4, 1.5 };
    const S: [5]f64 = .{ 1, 1, 1, 1, 1 };
    try std.testing.expectError(Error.NonUniformSpacing, spectralMoment(0, &omega, &S));
}

test "unsorted omega rejected" {
    const omega: [5]f64 = .{ 1.0, 1.1, 1.0, 1.3, 1.4 };
    const S: [5]f64 = .{ 1, 1, 1, 1, 1 };
    try std.testing.expectError(Error.OmegaNotSorted, spectralMoment(0, &omega, &S));
}

test "RAO amplification on a rectangular spectrum" {
    // S = 1 over [1, 3], |H|^2 = 4 over the whole band -> response m_0 = 8.
    var omega: [21]f64 = undefined;
    var S: [21]f64 = undefined;
    var H_sq: [21]f64 = undefined;
    var i: usize = 0;
    while (i < omega.len) : (i += 1) {
        omega[i] = 1.0 + 0.1 * @as(f64, @floatFromInt(i));
        S[i] = 1.0;
        H_sq[i] = 4.0;
    }
    var SR: [21]f64 = undefined;
    try responseSpectrum(&H_sq, &S, &SR);
    const m0_resp = try spectralMoment(0, &omega, &SR);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), m0_resp, 1e-12);
    const Hs = significantResponseAmplitude(m0_resp);
    try std.testing.expectApproxEqAbs(4.0 * @sqrt(8.0), Hs, 1e-12);
}
