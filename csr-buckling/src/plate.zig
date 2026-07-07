const std = @import("std");

pub const Error = error{
    NonPositiveDimension,
    InvalidPoissonRatio,
    NonPositiveModulus,
    NonPositiveYield,
    AspectRatioOutOfRange,
};

pub const BoundaryType = enum {
    /// Plate simply supported on all four edges.
    simply_supported_4_edges,
    /// Plate clamped on all four edges.
    clamped_4_edges,
};

pub const Loading = enum {
    /// Uniaxial uniform compression along the long edge.
    uniaxial_compression,
    /// Pure in-plane shear.
    shear,
};

/// Buckling coefficient `k` per classical plate theory.
///
/// For simply supported plates under uniaxial compression the minimum
/// occurs at `m = a/b` integer and equals 4.0. For general aspect
/// ratio alpha = a/b >= 1 the minimum-over-modes envelope is well
/// approximated by `k = (alpha/m + m/alpha)^2` with `m` chosen as the
/// nearest integer to alpha.
///
/// Clamped four-edge plates have `k ~ 6.97` at alpha = 1 with a long-
/// alpha asymptote of approximately 7.0.
///
/// For shear loading: simply supported `k = 5.34 + 4 / alpha^2`;
/// clamped `k = 8.98 + 5.6 / alpha^2`.
pub fn bucklingCoefficient(boundary: BoundaryType, loading: Loading, alpha: f64) Error!f64 {
    if (!(alpha >= 1.0)) return Error.AspectRatioOutOfRange;
    switch (loading) {
        .uniaxial_compression => switch (boundary) {
            .simply_supported_4_edges => {
                // Nearest integer m to alpha.
                const m_f: f64 = @round(alpha);
                const m: f64 = if (m_f < 1.0) 1.0 else m_f;
                const r = alpha / m + m / alpha;
                return r * r;
            },
            .clamped_4_edges => {
                // Clamped-edge minimum k over modes: closed-form envelope
                // 6.97 at alpha=1 decaying to ~7.0 asymptote.
                return 6.97 + 1.03 / (alpha * alpha);
            },
        },
        .shear => switch (boundary) {
            .simply_supported_4_edges => return 5.34 + 4.0 / (alpha * alpha),
            .clamped_4_edges => return 8.98 + 5.6 / (alpha * alpha),
        },
    }
}

/// Elastic critical stress sigma_cr = k pi^2 E / (12 (1 - nu^2)) (t/b)^2.
/// Inputs:
///   E_pa: Young modulus [Pa].
///   nu:   Poisson ratio [-]; physical range (0.0, 0.5).
///   t_m:  plate thickness [m].
///   b_m:  short-edge length [m].
///   k:    buckling coefficient [-]; from `bucklingCoefficient`.
/// Returns sigma_cr [Pa].
pub fn elasticCriticalStressPa(E_pa: f64, nu: f64, t_m: f64, b_m: f64, k: f64) Error!f64 {
    if (!(E_pa > 0)) return Error.NonPositiveModulus;
    if (!(nu > 0.0 and nu < 0.5)) return Error.InvalidPoissonRatio;
    if (!(t_m > 0)) return Error.NonPositiveDimension;
    if (!(b_m > 0)) return Error.NonPositiveDimension;
    const pi2 = std.math.pi * std.math.pi;
    const tb = t_m / b_m;
    return k * pi2 * E_pa / (12.0 * (1.0 - nu * nu)) * (tb * tb);
}

/// Johnson-parabola reduction of elastic critical stress per CSR
/// Section 8 when sigma_cr exceeds 0.5 sigma_yield.
/// Returns the effective critical stress sigma_eff:
///   sigma_eff = sigma_cr                        if sigma_cr <= 0.5 sigma_y
///   sigma_eff = sigma_y (1 - sigma_y/(4 sigma_cr))  otherwise.
pub fn johnsonReducedStressPa(sigma_cr_pa: f64, sigma_yield_pa: f64) Error!f64 {
    if (!(sigma_cr_pa > 0)) return Error.NonPositiveYield;
    if (!(sigma_yield_pa > 0)) return Error.NonPositiveYield;
    if (sigma_cr_pa <= 0.5 * sigma_yield_pa) return sigma_cr_pa;
    return sigma_yield_pa * (1.0 - sigma_yield_pa / (4.0 * sigma_cr_pa));
}

test "k for SS plate under uniaxial compression at alpha = 1 is 4" {
    const k = try bucklingCoefficient(.simply_supported_4_edges, .uniaxial_compression, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), k, 1e-12);
}

test "k for SS plate under uniaxial compression at alpha = 2 is 4" {
    const k = try bucklingCoefficient(.simply_supported_4_edges, .uniaxial_compression, 2.0);
    // alpha = 2, m = 2: (1 + 1)^2 = 4.
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), k, 1e-12);
}

test "k for clamped plate under uniaxial compression is ~7" {
    const k1 = try bucklingCoefficient(.clamped_4_edges, .uniaxial_compression, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), k1, 1e-12);
    const klarge = try bucklingCoefficient(.clamped_4_edges, .uniaxial_compression, 10.0);
    try std.testing.expect(klarge > 6.9 and klarge < 7.05);
}

test "k for SS plate under shear at alpha = 1 is 9.34" {
    const k = try bucklingCoefficient(.simply_supported_4_edges, .shear, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 9.34), k, 1e-12);
}

test "k for clamped plate under shear at alpha = 1 is 14.58" {
    const k = try bucklingCoefficient(.clamped_4_edges, .shear, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 14.58), k, 1e-12);
}

test "elastic critical stress for steel SS plate t/b = 1/50, k = 4" {
    // E = 210 GPa, nu = 0.3, t/b = 1/50.
    // sigma_cr = 4 * pi^2 * 210e9 / (12 * (1 - 0.09)) * (1/50)^2
    //         = 4 * pi^2 * 210e9 / 10.92 * 0.0004
    const sigma = try elasticCriticalStressPa(210e9, 0.3, 1.0, 50.0, 4.0);
    const expected = 4.0 * std.math.pi * std.math.pi * 210e9 / 10.92 * 0.0004;
    try std.testing.expectApproxEqAbs(expected, sigma, 1.0);
    // Order of magnitude: ~ 304 MPa.
    try std.testing.expect(sigma > 300e6 and sigma < 310e6);
}

test "elastic critical stress scales with (t/b)^2" {
    const s1 = try elasticCriticalStressPa(210e9, 0.3, 1.0, 50.0, 4.0);
    const s2 = try elasticCriticalStressPa(210e9, 0.3, 2.0, 50.0, 4.0);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), s2 / s1, 1e-9);
}

test "Johnson reduction: low sigma_cr passes through unchanged" {
    const out = try johnsonReducedStressPa(50e6, 235e6);
    try std.testing.expectApproxEqAbs(@as(f64, 50e6), out, 1.0);
}

test "Johnson reduction: high sigma_cr reduced toward yield" {
    // sigma_cr = 500 MPa, sigma_y = 235 MPa.
    // sigma_eff = 235 (1 - 235 / (4 * 500)) = 235 (1 - 0.1175) = 235 * 0.8825
    //          = 207.3875 MPa.
    const out = try johnsonReducedStressPa(500e6, 235e6);
    try std.testing.expectApproxEqAbs(@as(f64, 207.3875e6), out, 1.0);
}

test "Johnson reduction: very high sigma_cr asymptotes to yield" {
    const out = try johnsonReducedStressPa(1e12, 355e6);
    try std.testing.expect(out > 0.99 * 355e6 and out < 355e6);
}

test "input rejection: non-positive thickness" {
    try std.testing.expectError(Error.NonPositiveDimension, elasticCriticalStressPa(210e9, 0.3, 0.0, 50.0, 4.0));
}

test "input rejection: invalid Poisson ratio" {
    try std.testing.expectError(Error.InvalidPoissonRatio, elasticCriticalStressPa(210e9, -0.1, 1.0, 50.0, 4.0));
    try std.testing.expectError(Error.InvalidPoissonRatio, elasticCriticalStressPa(210e9, 0.6, 1.0, 50.0, 4.0));
}

test "input rejection: aspect ratio below 1" {
    try std.testing.expectError(Error.AspectRatioOutOfRange, bucklingCoefficient(.simply_supported_4_edges, .uniaxial_compression, 0.8));
}
