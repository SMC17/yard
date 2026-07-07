const std = @import("std");

pub const Error = error{
    NonPositiveDimension,
    NonPositiveModulus,
    NonPositiveYield,
    NonPositiveLength,
};

pub const EndCondition = enum {
    /// Pinned-pinned, mu = 1.0.
    pinned_pinned,
    /// Fixed-pinned, mu = 0.7.
    fixed_pinned,
    /// Fixed-fixed, mu = 0.5.
    fixed_fixed,
    /// Fixed-free (cantilever), mu = 2.0.
    fixed_free,
};

/// Effective-length factor mu for classical column boundary conditions.
pub fn effectiveLengthFactor(end: EndCondition) f64 {
    return switch (end) {
        .pinned_pinned => 1.0,
        .fixed_pinned => 0.7,
        .fixed_fixed => 0.5,
        .fixed_free => 2.0,
    };
}

/// Euler critical load P_cr = pi^2 E I / (mu L)^2.
/// Inputs in SI: E [Pa], I [m^4], L [m]. Returns P_cr [N].
pub fn eulerCriticalLoadN(E_pa: f64, I_m4: f64, L_m: f64, end: EndCondition) Error!f64 {
    if (!(E_pa > 0)) return Error.NonPositiveModulus;
    if (!(I_m4 > 0)) return Error.NonPositiveDimension;
    if (!(L_m > 0)) return Error.NonPositiveLength;
    const mu = effectiveLengthFactor(end);
    const Le = mu * L_m;
    const pi2 = std.math.pi * std.math.pi;
    return pi2 * E_pa * I_m4 / (Le * Le);
}

/// Euler critical stress sigma_cr = P_cr / A. Inputs SI; returns Pa.
pub fn eulerCriticalStressPa(E_pa: f64, I_m4: f64, A_m2: f64, L_m: f64, end: EndCondition) Error!f64 {
    if (!(A_m2 > 0)) return Error.NonPositiveDimension;
    const Pcr = try eulerCriticalLoadN(E_pa, I_m4, L_m, end);
    return Pcr / A_m2;
}

/// Slenderness ratio lambda = mu L / sqrt(I/A).
pub fn slendernessRatio(I_m4: f64, A_m2: f64, L_m: f64, end: EndCondition) Error!f64 {
    if (!(I_m4 > 0)) return Error.NonPositiveDimension;
    if (!(A_m2 > 0)) return Error.NonPositiveDimension;
    if (!(L_m > 0)) return Error.NonPositiveLength;
    const mu = effectiveLengthFactor(end);
    const r = @sqrt(I_m4 / A_m2);
    return mu * L_m / r;
}

/// Reference Euler stress for a slenderness ratio:
/// sigma_E = pi^2 E / lambda^2. Provided so callers can switch
/// between (E, I, A, L) and a direct lambda formulation.
pub fn eulerCriticalStressFromLambdaPa(E_pa: f64, lambda: f64) Error!f64 {
    if (!(E_pa > 0)) return Error.NonPositiveModulus;
    if (!(lambda > 0)) return Error.NonPositiveLength;
    const pi2 = std.math.pi * std.math.pi;
    return pi2 * E_pa / (lambda * lambda);
}

test "effectiveLengthFactor enumerates the four cases" {
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), effectiveLengthFactor(.pinned_pinned), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.7), effectiveLengthFactor(.fixed_pinned), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), effectiveLengthFactor(.fixed_fixed), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), effectiveLengthFactor(.fixed_free), 1e-12);
}

test "Euler critical load for unit pinned-pinned column" {
    // E=1, I=1, L=1, pinned-pinned -> P_cr = pi^2.
    const P = try eulerCriticalLoadN(1.0, 1.0, 1.0, .pinned_pinned);
    try std.testing.expectApproxEqAbs(std.math.pi * std.math.pi, P, 1e-12);
}

test "fixed-fixed column has 4x the Euler load of pinned-pinned" {
    const P_pp = try eulerCriticalLoadN(210e9, 1e-6, 3.0, .pinned_pinned);
    const P_ff = try eulerCriticalLoadN(210e9, 1e-6, 3.0, .fixed_fixed);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), P_ff / P_pp, 1e-9);
}

test "cantilever has 1/4 the Euler load of pinned-pinned" {
    const P_pp = try eulerCriticalLoadN(210e9, 1e-6, 3.0, .pinned_pinned);
    const P_cant = try eulerCriticalLoadN(210e9, 1e-6, 3.0, .fixed_free);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), P_cant / P_pp, 1e-9);
}

test "Euler critical stress for steel I-section" {
    // E = 210 GPa, I = 1e-6 m^4, A = 1e-3 m^2, L = 3 m, pinned-pinned.
    const sigma = try eulerCriticalStressPa(210e9, 1e-6, 1e-3, 3.0, .pinned_pinned);
    // sigma = pi^2 * 210e9 * 1e-6 / (1 * 3)^2 / 1e-3
    //       = pi^2 * 23.333e6 Pa  ~= 230 MPa.
    const expected = std.math.pi * std.math.pi * 210e9 * 1e-6 / 9.0 / 1e-3;
    try std.testing.expectApproxEqAbs(expected, sigma, 1.0);
    try std.testing.expect(sigma > 2.0e8 and sigma < 2.5e8);
}

test "slenderness ratio for square section" {
    // A = b^2 = 0.04, I = b^4/12 = 0.04^2/12 = 0.000133...
    // r = sqrt(I/A) = sqrt(0.04/12) = 0.0577 m.
    // L = 3, pinned-pinned -> lambda = 3 / 0.0577 = 52.0.
    const A: f64 = 0.04;
    const I: f64 = A * A / 12.0;
    const lambda = try slendernessRatio(I, A, 3.0, .pinned_pinned);
    const r_expected = @sqrt(I / A);
    try std.testing.expectApproxEqAbs(3.0 / r_expected, lambda, 1e-9);
}

test "fixed-pinned slenderness is 0.7 of pinned-pinned" {
    const I: f64 = 1e-6;
    const A: f64 = 1e-3;
    const l_pp = try slendernessRatio(I, A, 3.0, .pinned_pinned);
    const l_fp = try slendernessRatio(I, A, 3.0, .fixed_pinned);
    try std.testing.expectApproxEqAbs(@as(f64, 0.7), l_fp / l_pp, 1e-9);
}

test "eulerCriticalStressFromLambdaPa matches pi^2 E / lambda^2" {
    const lambda: f64 = 80.0;
    const E: f64 = 210e9;
    const s = try eulerCriticalStressFromLambdaPa(E, lambda);
    const expected = std.math.pi * std.math.pi * E / (lambda * lambda);
    try std.testing.expectApproxEqAbs(expected, s, 1e-3);
}

test "input rejection: non-positive area" {
    try std.testing.expectError(Error.NonPositiveDimension, eulerCriticalStressPa(210e9, 1e-6, 0.0, 3.0, .pinned_pinned));
}

test "input rejection: non-positive length" {
    try std.testing.expectError(Error.NonPositiveLength, eulerCriticalLoadN(210e9, 1e-6, 0.0, .pinned_pinned));
}
