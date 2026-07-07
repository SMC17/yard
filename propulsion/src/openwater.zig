// Open-water curve fitting + Reynolds correction + eta_R relative
// rotative efficiency.

const std = @import("std");

pub const Error = error{
    NonPositiveJ,
    NonPositiveReynolds,
    InvalidEta,
    UnequalLength,
    InsufficientPoints,
};

/// Open-water efficiency at advance ratio J:
///   eta_0 = J / (2 pi) * (K_T / K_Q).
pub fn openWaterEfficiency(K_T: f64, K_Q: f64, J: f64) Error!f64 {
    if (!(J > 0)) return Error.NonPositiveJ;
    if (!(K_Q > 0)) return Error.InvalidEta;
    return J / (2.0 * std.math.pi) * K_T / K_Q;
}

/// ITTC-78 Reynolds correction to Wageningen K_T and K_Q (full-scale
/// vs model-scale, Re based on 0.7 R chord):
///   delta_K_T = -0.3 (C_D_M - C_D_S) (P/D) (A_E/A_0) Z
///   delta_K_Q = +0.25 (C_D_M - C_D_S) (P/D) (A_E/A_0) Z / D
/// with C_D = 2 (1 + 2 t/c) (0.044 / Re^(1/6) - 5 / Re^(2/3)) the
/// Lerbs friction coefficient.
pub fn lerbsFrictionCoefficient(
    chord_thickness_ratio: f64,
    Re: f64,
) Error!f64 {
    if (!(Re > 0)) return Error.NonPositiveReynolds;
    if (!(chord_thickness_ratio >= 0)) return Error.InvalidEta;
    return 2.0 * (1.0 + 2.0 * chord_thickness_ratio) *
        (0.044 / std.math.pow(f64, Re, 1.0 / 6.0) -
            5.0 / std.math.pow(f64, Re, 2.0 / 3.0));
}

pub fn reynoldsCorrectionKT(
    C_D_M: f64,
    C_D_S: f64,
    P_over_D: f64,
    A_E_over_A0: f64,
    Z: u32,
) f64 {
    const Z_f: f64 = @floatFromInt(Z);
    return -0.3 * (C_D_M - C_D_S) * P_over_D * A_E_over_A0 * Z_f;
}

pub fn reynoldsCorrectionKQ(
    C_D_M: f64,
    C_D_S: f64,
    P_over_D: f64,
    A_E_over_A0: f64,
    Z: u32,
) f64 {
    const Z_f: f64 = @floatFromInt(Z);
    return 0.25 * (C_D_M - C_D_S) * P_over_D * A_E_over_A0 * Z_f;
}

/// Three-point quadratic fit of K_T(J) or K_Q(J) for design-spiral
/// interpolation. Inputs at J_1 < J_2 < J_3 with corresponding
/// values y_1, y_2, y_3.
pub const Quadratic = struct { a: f64, b: f64, c: f64 };

pub fn fitQuadraticThreePoint(
    J_arr: [3]f64,
    K_arr: [3]f64,
) Error!Quadratic {
    if (!(J_arr[0] < J_arr[1] and J_arr[1] < J_arr[2])) return Error.NonPositiveJ;
    // Solve Vandermonde 3x3 directly.
    const x1 = J_arr[0];
    const x2 = J_arr[1];
    const x3 = J_arr[2];
    const y1 = K_arr[0];
    const y2 = K_arr[1];
    const y3 = K_arr[2];
    const det = (x1 - x2) * (x1 - x3) * (x2 - x3);
    if (@abs(det) < 1e-30) return Error.InsufficientPoints;
    const a = (x3 * (y2 - y1) + x2 * (y1 - y3) + x1 * (y3 - y2)) / det;
    const b = (x3 * x3 * (y1 - y2) + x2 * x2 * (y3 - y1) + x1 * x1 * (y2 - y3)) / det;
    const c = (x2 * x3 * (x2 - x3) * y1 + x3 * x1 * (x3 - x1) * y2 + x1 * x2 * (x1 - x2) * y3) / det;
    return .{ .a = a, .b = b, .c = c };
}

pub fn evaluateQuadratic(q: Quadratic, J: f64) f64 {
    return q.a * J * J + q.b * J + q.c;
}

/// Relative rotative efficiency eta_R for single-screw merchant ships
/// per Holtrop-Mennen 1984:
///   eta_R = 0.9922 - 0.05908 (A_E/A_0) + 0.07424 (C_P - 0.0225 lcb)
/// where lcb is in percent of L_PP. Twin-screw:
///   eta_R = 0.9737 + 0.111 (C_P - 0.0225 lcb) - 0.06325 P/D.
pub fn etaRSingleScrew(
    A_E_over_A0: f64,
    C_P: f64,
    lcb_percent: f64,
) Error!f64 {
    if (!(A_E_over_A0 > 0)) return Error.InvalidEta;
    if (!(C_P > 0 and C_P < 1.0)) return Error.InvalidEta;
    return 0.9922 - 0.05908 * A_E_over_A0 + 0.07424 * (C_P - 0.0225 * lcb_percent);
}

pub fn etaRTwinScrew(
    C_P: f64,
    lcb_percent: f64,
    P_over_D: f64,
) Error!f64 {
    if (!(C_P > 0 and C_P < 1.0)) return Error.InvalidEta;
    if (!(P_over_D > 0)) return Error.InvalidEta;
    return 0.9737 + 0.111 * (C_P - 0.0225 * lcb_percent) - 0.06325 * P_over_D;
}

/// Find J at peak open-water efficiency by brute-force search.
pub fn peakEfficiencyJ(
    quad_K_T: Quadratic,
    quad_K_Q: Quadratic,
    J_lo: f64,
    J_hi: f64,
) Error!f64 {
    if (!(J_lo > 0 and J_hi > J_lo)) return Error.NonPositiveJ;
    var best_J: f64 = J_lo;
    var best_eta: f64 = 0.0;
    const N: usize = 100;
    var i: usize = 0;
    while (i <= N) : (i += 1) {
        const t: f64 = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(N));
        const J = J_lo + t * (J_hi - J_lo);
        const KT = evaluateQuadratic(quad_K_T, J);
        const KQ = evaluateQuadratic(quad_K_Q, J);
        if (KQ <= 0) continue;
        const eta = J / (2.0 * std.math.pi) * KT / KQ;
        if (eta > best_eta) {
            best_eta = eta;
            best_J = J;
        }
    }
    return best_J;
}

test "open-water efficiency closed form" {
    const eta = try openWaterEfficiency(0.20, 0.04, 0.6);
    const expected = 0.6 / (2.0 * std.math.pi) * 0.20 / 0.04;
    try std.testing.expectApproxEqAbs(expected, eta, 1e-12);
}

test "open-water efficiency at J=0 rejected" {
    try std.testing.expectError(Error.NonPositiveJ, openWaterEfficiency(0.20, 0.04, 0.0));
}

test "Lerbs friction at Re=1e6, t/c=0.05" {
    const C_D = try lerbsFrictionCoefficient(0.05, 1.0e6);
    const expected = 2.0 * 1.10 *
        (0.044 / std.math.pow(f64, @as(f64, 1.0e6), 1.0 / 6.0) -
            5.0 / std.math.pow(f64, @as(f64, 1.0e6), 2.0 / 3.0));
    try std.testing.expectApproxEqAbs(expected, C_D, 1e-12);
}

test "Lerbs friction decreases with Re" {
    const c1 = try lerbsFrictionCoefficient(0.05, 1.0e5);
    const c2 = try lerbsFrictionCoefficient(0.05, 1.0e7);
    try std.testing.expect(c2 < c1);
}

test "Reynolds correction K_T sign: model > ship gives negative correction" {
    const dKT = reynoldsCorrectionKT(0.01, 0.005, 1.0, 0.7, 4);
    // (C_D_M - C_D_S) = 0.005, so correction is negative.
    try std.testing.expect(dKT < 0);
}

test "Reynolds correction K_Q sign: model > ship gives positive correction" {
    const dKQ = reynoldsCorrectionKQ(0.01, 0.005, 1.0, 0.7, 4);
    try std.testing.expect(dKQ > 0);
}

test "quadratic fit recovers a parabola" {
    // Fit y = 2 x^2 - 3 x + 1.
    const J = [_]f64{ 0.2, 0.5, 0.8 };
    const K = [_]f64{ 0.48, -0.000, 0.880 };
    const fitted = K[0]; _ = fitted;
    const known_a = 2.0;
    const known_b = -3.0;
    const known_c = 1.0;
    const exact = [_]f64{
        known_a * J[0] * J[0] + known_b * J[0] + known_c,
        known_a * J[1] * J[1] + known_b * J[1] + known_c,
        known_a * J[2] * J[2] + known_b * J[2] + known_c,
    };
    const q = try fitQuadraticThreePoint(J, exact);
    try std.testing.expectApproxEqAbs(known_a, q.a, 1e-9);
    try std.testing.expectApproxEqAbs(known_b, q.b, 1e-9);
    try std.testing.expectApproxEqAbs(known_c, q.c, 1e-9);
}

test "evaluateQuadratic matches input points" {
    const q = Quadratic{ .a = 2.0, .b = -3.0, .c = 1.0 };
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0 * 0.25 - 1.5 + 1.0),
        evaluateQuadratic(q, 0.5),
        1e-12,
    );
}

test "fit rejects non-monotone J" {
    const J = [_]f64{ 0.5, 0.2, 0.8 };
    const K = [_]f64{ 0.5, 0.3, 0.1 };
    try std.testing.expectError(Error.NonPositiveJ, fitQuadraticThreePoint(J, K));
}

test "eta_R single-screw at A_E/A_0=0.7, C_P=0.6, lcb=-1" {
    const er = try etaRSingleScrew(0.7, 0.6, -1.0);
    const expected = 0.9922 - 0.05908 * 0.7 + 0.07424 * (0.6 - 0.0225 * -1.0);
    try std.testing.expectApproxEqAbs(expected, er, 1e-12);
}

test "eta_R twin-screw at C_P=0.6, lcb=-1, P/D=1.0" {
    const er = try etaRTwinScrew(0.6, -1.0, 1.0);
    const expected = 0.9737 + 0.111 * (0.6 - 0.0225 * -1.0) - 0.06325 * 1.0;
    try std.testing.expectApproxEqAbs(expected, er, 1e-12);
}

test "eta_R typically in [0.95, 1.05]" {
    const er = try etaRSingleScrew(0.7, 0.65, 0.0);
    try std.testing.expect(er > 0.95 and er < 1.05);
}

test "peakEfficiencyJ finds positive J in bracket" {
    // Constant-shape: K_T = -0.5 J + 0.3 (decreasing), K_Q = -0.1 J + 0.06.
    const KT = Quadratic{ .a = 0.0, .b = -0.5, .c = 0.3 };
    const KQ = Quadratic{ .a = 0.0, .b = -0.1, .c = 0.06 };
    const J_peak = try peakEfficiencyJ(KT, KQ, 0.1, 0.5);
    try std.testing.expect(J_peak >= 0.1 and J_peak <= 0.5);
}

test "input rejection: C_P >= 1 in eta_R" {
    try std.testing.expectError(Error.InvalidEta, etaRSingleScrew(0.7, 1.1, 0.0));
}
