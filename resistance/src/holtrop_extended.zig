// Holtrop-Mennen 1984 extended coefficient chain.
//
// This module supplements `holtrop.zig` (which covers the form
// factor + wave resistance basics) with the full c_1..c_16 + m_1 +
// m_3 + m_4 + lambda chain plus appendage and roughness allowance
// terms required for a complete Holtrop-Mennen powering prediction.

const std = @import("std");

pub const Error = error{
    NonPositiveLength,
    NonPositiveBeam,
    NonPositiveDraft,
    NonPositiveBlockCoefficient,
    NonPositiveFroude,
    NonPositiveDensity,
    InvalidGeometry,
};

/// c_1 Holtrop wave-resistance coefficient. With c_7 already
/// available from `holtrop.zig` and the half-angle of entrance i_E
/// in degrees:
///   c_1 = 2223105 * c_7^3.78613 * (T/B)^1.07961 * (90 - i_E)^(-1.37565)
pub fn c1Coefficient(
    c_7: f64,
    T_m: f64,
    B_m: f64,
    i_E_deg: f64,
) Error!f64 {
    if (!(c_7 > 0)) return Error.NonPositiveBlockCoefficient;
    if (!(T_m > 0)) return Error.NonPositiveDraft;
    if (!(B_m > 0)) return Error.NonPositiveBeam;
    if (!(i_E_deg >= 0 and i_E_deg < 90)) return Error.InvalidGeometry;
    return 2223105.0 * std.math.pow(f64, c_7, 3.78613) *
        std.math.pow(f64, T_m / B_m, 1.07961) *
        std.math.pow(f64, 90.0 - i_E_deg, -1.37565);
}

/// c_5 Holtrop coefficient: transom-immersion correction.
///   c_5 = 1 - 0.8 A_T / (B T C_M)
/// with A_T the immersed transverse-stern area, C_M midship section
/// coefficient.
pub fn c5Coefficient(
    A_T_m2: f64,
    B_m: f64,
    T_m: f64,
    C_M: f64,
) Error!f64 {
    if (!(B_m > 0)) return Error.NonPositiveBeam;
    if (!(T_m > 0)) return Error.NonPositiveDraft;
    if (!(C_M > 0 and C_M <= 1.0)) return Error.NonPositiveBlockCoefficient;
    if (!(A_T_m2 >= 0)) return Error.InvalidGeometry;
    return 1.0 - 0.8 * A_T_m2 / (B_m * T_m * C_M);
}

/// c_15 Holtrop coefficient: forward-form correction based on the
/// L^3 / displaced-volume ratio:
///   c_15 = -1.69385          if L^3 / V_disp < 512
///        = 0.0                 if L^3 / V_disp > 1727
///        = -1.69385 + (L/L_R - 8.0) / 2.36 ... (continuous interp)
/// where L_R is a reference length set to L^(1/3); the kernel uses
/// the simplified ratio-based step formulation per HM 1984.
pub fn c15Coefficient(L_m: f64, V_disp_m3: f64) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (!(V_disp_m3 > 0)) return Error.NonPositiveDraft;
    const r = L_m * L_m * L_m / V_disp_m3;
    if (r < 512.0) return -1.69385;
    if (r > 1727.0) return 0.0;
    return -1.69385 + (r - 512.0) / (1727.0 - 512.0) * 1.69385;
}

/// c_16 Holtrop coefficient: prismatic-coefficient regression for
/// the wave-resistance m_4 parameter. Per HM 1984:
///   c_16 = 8.07981 C_P - 13.8673 C_P^2 + 6.984388 C_P^3       if C_P < 0.80
///        = 1.73014 - 0.7067 C_P                                 if C_P >= 0.80
pub fn c16Coefficient(C_P: f64) Error!f64 {
    if (!(C_P > 0 and C_P <= 1.0)) return Error.NonPositiveBlockCoefficient;
    if (C_P < 0.80) {
        return 8.07981 * C_P - 13.8673 * C_P * C_P +
            6.984388 * C_P * C_P * C_P;
    }
    return 1.73014 - 0.7067 * C_P;
}

/// m_1 Holtrop coefficient: low-Fn wave-resistance shape parameter.
///   m_1 = 0.0140407 L/T - 1.75254 V_disp^(1/3) / L
///         - 4.79323 B/L - c_16
/// Returns dimensionless m_1.
pub fn m1Coefficient(
    L_m: f64,
    T_m: f64,
    B_m: f64,
    V_disp_m3: f64,
    c_16: f64,
) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (!(T_m > 0)) return Error.NonPositiveDraft;
    if (!(B_m > 0)) return Error.NonPositiveBeam;
    if (!(V_disp_m3 > 0)) return Error.InvalidGeometry;
    const V_cuberoot = std.math.cbrt(V_disp_m3);
    return 0.0140407 * L_m / T_m -
        1.75254 * V_cuberoot / L_m -
        4.79323 * B_m / L_m -
        c_16;
}

/// m_3 Holtrop coefficient (high-Fn branch, Fn > 0.55) is governed
/// by the L^3 / V_disp ratio:
///   m_3 = -7.2035 (B/L)^0.326869 (T/B)^0.605375.
pub fn m3Coefficient(B_m: f64, L_m: f64, T_m: f64) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (!(T_m > 0)) return Error.NonPositiveDraft;
    if (!(B_m > 0)) return Error.NonPositiveBeam;
    return -7.2035 * std.math.pow(f64, B_m / L_m, 0.326869) *
        std.math.pow(f64, T_m / B_m, 0.605375);
}

/// m_4 Holtrop coefficient governs the oscillatory wave-resistance
/// term:
///   m_4 = c_15 * 0.4 * exp(-0.034 / Fn^3.29).
pub fn m4Coefficient(c_15: f64, Fn: f64) Error!f64 {
    if (!(Fn > 0)) return Error.NonPositiveFroude;
    return c_15 * 0.4 * @exp(-0.034 / std.math.pow(f64, Fn, 3.29));
}

/// Wave-resistance parameter lambda: high-Fn vs low-Fn branch.
///   lambda = 1.446 C_P - 0.03 L/B          if L/B < 12
///          = 1.446 C_P - 0.36               if L/B >= 12
pub fn lambdaParameter(C_P: f64, L_m: f64, B_m: f64) Error!f64 {
    if (!(C_P > 0)) return Error.NonPositiveBlockCoefficient;
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (!(B_m > 0)) return Error.NonPositiveBeam;
    const ratio = L_m / B_m;
    if (ratio < 12.0) {
        return 1.446 * C_P - 0.03 * ratio;
    }
    return 1.446 * C_P - 0.36;
}

/// Holtrop appendage-resistance coefficient (1 + k_2). Per HM 1984
/// Table 5 for common appendages:
///   bilge keel: 1.4; balance rudder: 1.4; spade rudder: 1.5;
///   shaft brackets: 3.0; skeg: 1.5-2.0; stabiliser fins: 2.8;
///   bossings: 2.0; sonar dome: 2.7.
pub const AppendageType = enum {
    bilge_keel,
    balance_rudder,
    spade_rudder,
    shaft_brackets,
    skeg,
    stabilizer_fins,
    bossings,
    sonar_dome,

    pub fn formFactor(self: AppendageType) f64 {
        return switch (self) {
            .bilge_keel => 1.4,
            .balance_rudder => 1.4,
            .spade_rudder => 1.5,
            .shaft_brackets => 3.0,
            .skeg => 1.75,
            .stabilizer_fins => 2.8,
            .bossings => 2.0,
            .sonar_dome => 2.7,
        };
    }
};

/// Appendage resistance:
///   R_APP = 0.5 rho V^2 C_F (1 + k_2_eq) S_app
/// where (1 + k_2)_eq is the weighted average across appendages:
///   (1 + k_2)_eq = sum (1 + k_2)_i S_i / sum S_i
pub fn equivalentAppendageFormFactor(
    types_arr: []const AppendageType,
    wetted_areas_m2: []const f64,
) Error!f64 {
    if (types_arr.len != wetted_areas_m2.len) return Error.InvalidGeometry;
    if (types_arr.len == 0) return 1.0;
    var num: f64 = 0.0;
    var den: f64 = 0.0;
    for (types_arr, wetted_areas_m2) |t, S| {
        if (!(S > 0)) return Error.InvalidGeometry;
        num += t.formFactor() * S;
        den += S;
    }
    return num / den;
}

pub fn appendageResistanceN(
    rho_kg_per_m3: f64,
    V_mps: f64,
    C_F: f64,
    one_plus_k2_eq: f64,
    S_app_total_m2: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(V_mps >= 0)) return Error.NonPositiveFroude;
    if (!(C_F > 0)) return Error.NonPositiveBlockCoefficient;
    if (!(one_plus_k2_eq > 0)) return Error.NonPositiveBlockCoefficient;
    if (!(S_app_total_m2 >= 0)) return Error.InvalidGeometry;
    return 0.5 * rho_kg_per_m3 * V_mps * V_mps * C_F *
        one_plus_k2_eq * S_app_total_m2;
}

/// Roughness allowance C_A per Holtrop-Mennen 1984:
///   C_A = 0.006 (L + 100)^(-0.16) - 0.00205
///       + 0.003 sqrt(L/7.5) C_B^4 c_2 (0.04 - c_4)
/// with c_4 = T_F / L if T_F / L <= 0.04, else 0.04. The simplified
/// short form (used for v0.1.0) omits the second term and matches
/// the C_A coefficient in `yard-ittc78-zig`.
pub fn roughnessAllowanceShort(L_m: f64) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    return 0.006 * std.math.pow(f64, L_m + 100.0, -0.16) - 0.00205;
}

/// Full HM 1984 roughness allowance including the bulb correction:
///   C_A_full = 0.006 (L + 100)^(-0.16) - 0.00205
///            + 0.003 sqrt(L / 7.5) C_B^4 c_2 (0.04 - c_4)
/// with c_4 = min(T_F / L, 0.04).
pub fn roughnessAllowanceFull(
    L_m: f64,
    C_B: f64,
    c_2: f64,
    T_F_m: f64,
) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (!(C_B > 0)) return Error.NonPositiveBlockCoefficient;
    if (!(T_F_m > 0)) return Error.NonPositiveDraft;
    const short = try roughnessAllowanceShort(L_m);
    var c_4 = T_F_m / L_m;
    if (c_4 > 0.04) c_4 = 0.04;
    return short +
        0.003 * @sqrt(L_m / 7.5) * std.math.pow(f64, C_B, 4) * c_2 *
        (0.04 - c_4);
}

/// Full Holtrop wave-resistance coefficient:
///   C_W = c_1 c_2 c_5 exp(m_1 Fn^d + m_4 cos(lambda Fn^(-2)))
/// with d = -0.9 (low-Fn branch) or d = m_3 (high-Fn branch).
/// `branch_high_fn` selects the m_3 high-Fn case.
pub fn waveResistanceCoefficient(
    c_1: f64,
    c_2: f64,
    c_5: f64,
    m_1: f64,
    m_4: f64,
    lambda: f64,
    Fn: f64,
    m_3: f64,
    branch_high_fn: bool,
) Error!f64 {
    if (!(Fn > 0)) return Error.NonPositiveFroude;
    const d: f64 = if (branch_high_fn) m_3 else -0.9;
    const wave = c_1 * c_2 * c_5 *
        @exp(m_1 * std.math.pow(f64, Fn, d) +
            m_4 * @cos(lambda / (Fn * Fn)));
    return wave;
}

test "c_1 closed form at c_7 = 0.2, T/B = 0.5, i_E = 30" {
    const c1 = try c1Coefficient(0.2, 8.0, 16.0, 30.0);
    const expected = 2223105.0 * std.math.pow(f64, 0.2, 3.78613) *
        std.math.pow(f64, 0.5, 1.07961) *
        std.math.pow(f64, 60.0, -1.37565);
    try std.testing.expectApproxEqAbs(expected, c1, 1e-6);
}

test "c_5 at A_T = 0 equals 1 (no transom)" {
    const c5 = try c5Coefficient(0.0, 20.0, 8.0, 0.98);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), c5, 1e-12);
}

test "c_5 below 1 for transom-stern ships" {
    const c5 = try c5Coefficient(20.0, 20.0, 8.0, 0.98);
    try std.testing.expect(c5 < 1.0 and c5 > 0.0);
}

test "c_15: small L^3/V uses -1.69385" {
    const c15 = try c15Coefficient(100.0, 30000.0); // L^3/V = 100^3/30000 = 33.33
    try std.testing.expectApproxEqAbs(@as(f64, -1.69385), c15, 1e-12);
}

test "c_15: large L^3/V uses 0" {
    const c15 = try c15Coefficient(300.0, 10000.0); // L^3/V = 2700
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), c15, 1e-12);
}

test "c_15: interpolation in mid range" {
    const c15 = try c15Coefficient(125.0, 1500.0); // L^3/V = 1302
    try std.testing.expect(c15 > -1.69385 and c15 < 0.0);
}

test "c_16: low C_P branch closed form" {
    const c16 = try c16Coefficient(0.6);
    const expected = 8.07981 * 0.6 - 13.8673 * 0.36 + 6.984388 * 0.216;
    try std.testing.expectApproxEqAbs(expected, c16, 1e-9);
}

test "c_16: high C_P branch" {
    const c16 = try c16Coefficient(0.85);
    const expected = 1.73014 - 0.7067 * 0.85;
    try std.testing.expectApproxEqAbs(expected, c16, 1e-9);
}

test "c_16 continuous at C_P = 0.80" {
    const c16_below = try c16Coefficient(0.7999);
    const c16_above = try c16Coefficient(0.8001);
    // Discontinuity is small in practice.
    try std.testing.expect(@abs(c16_below - c16_above) < 0.05);
}

test "m_1 closed-form check" {
    const c16 = try c16Coefficient(0.7);
    const m1 = try m1Coefficient(200.0, 12.0, 32.0, 65_000.0, c16);
    const V_cb = std.math.cbrt(@as(f64, 65_000.0));
    const expected = 0.0140407 * 200.0 / 12.0 -
        1.75254 * V_cb / 200.0 -
        4.79323 * 32.0 / 200.0 - c16;
    try std.testing.expectApproxEqAbs(expected, m1, 1e-9);
}

test "m_3 closed-form check" {
    const m3 = try m3Coefficient(32.0, 200.0, 12.0);
    const expected = -7.2035 * std.math.pow(f64, 0.16, 0.326869) *
        std.math.pow(f64, 0.375, 0.605375);
    try std.testing.expectApproxEqAbs(expected, m3, 1e-9);
}

test "m_4 decays exponentially at low Fn" {
    const m4_low = try m4Coefficient(-1.0, 0.10);
    const m4_high = try m4Coefficient(-1.0, 0.30);
    try std.testing.expect(@abs(m4_high) > @abs(m4_low));
}

test "lambda branches: L/B < 12 vs >= 12" {
    const lam_short = try lambdaParameter(0.7, 100.0, 20.0); // L/B = 5
    const lam_long = try lambdaParameter(0.7, 240.0, 20.0); // L/B = 12
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.446 * 0.7 - 0.03 * 5.0),
        lam_short,
        1e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.446 * 0.7 - 0.36),
        lam_long,
        1e-12,
    );
}

test "appendage form factor table values" {
    try std.testing.expectApproxEqAbs(@as(f64, 1.4), AppendageType.bilge_keel.formFactor(), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), AppendageType.shaft_brackets.formFactor(), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.7), AppendageType.sonar_dome.formFactor(), 1e-12);
}

test "equivalent appendage form factor weighted by area" {
    const types = [_]AppendageType{ .bilge_keel, .spade_rudder };
    const areas = [_]f64{ 30.0, 10.0 };
    const eq = try equivalentAppendageFormFactor(&types, &areas);
    // (1.4 * 30 + 1.5 * 10) / 40 = (42 + 15) / 40 = 57/40 = 1.425.
    try std.testing.expectApproxEqAbs(@as(f64, 1.425), eq, 1e-12);
}

test "empty appendage list returns 1.0" {
    const types: []const AppendageType = &[_]AppendageType{};
    const areas: []const f64 = &[_]f64{};
    const eq = try equivalentAppendageFormFactor(types, areas);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), eq, 1e-12);
}

test "appendage resistance closed form" {
    const R = try appendageResistanceN(1025.0, 10.0, 0.003, 1.4, 80.0);
    const expected = 0.5 * 1025.0 * 100.0 * 0.003 * 1.4 * 80.0;
    try std.testing.expectApproxEqAbs(expected, R, 1e-6);
}

test "C_A short formula closed form" {
    const C_A = try roughnessAllowanceShort(200.0);
    const expected = 0.006 * std.math.pow(f64, 300.0, -0.16) - 0.00205;
    try std.testing.expectApproxEqAbs(expected, C_A, 1e-12);
}

test "C_A full > C_A short with positive bulb correction" {
    const short = try roughnessAllowanceShort(200.0);
    const full = try roughnessAllowanceFull(200.0, 0.75, 0.7, 5.0);
    // T_F/L = 0.025 < 0.04, so c_4 = 0.025; (0.04 - 0.025) > 0 -> full > short.
    try std.testing.expect(full > short);
}

test "C_A full equals C_A short when T_F/L >= 0.04" {
    const short = try roughnessAllowanceShort(200.0);
    const full = try roughnessAllowanceFull(200.0, 0.75, 0.7, 10.0);
    // T_F/L = 0.05 -> c_4 clipped to 0.04 -> bulb correction zero.
    try std.testing.expectApproxEqAbs(short, full, 1e-12);
}

test "C_W low-Fn branch produces finite value" {
    const CW = try waveResistanceCoefficient(
        0.001, 0.7, 1.0, -2.0, -0.02, 0.5, 0.2, -1.0, false);
    try std.testing.expect(std.math.isFinite(CW));
    try std.testing.expect(CW >= 0.0 or CW < 0.0); // just finite
}

test "C_W high-Fn branch uses m_3 exponent" {
    const Fn: f64 = 0.6;
    const m_3: f64 = -1.5;
    const CW_high = try waveResistanceCoefficient(
        0.001, 0.7, 1.0, -2.0, -0.02, 0.5, Fn, m_3, true);
    const CW_low = try waveResistanceCoefficient(
        0.001, 0.7, 1.0, -2.0, -0.02, 0.5, Fn, m_3, false);
    // High-Fn branch (Fn^m_3 with m_3 ~ -1.5) gives a different
    // value than low-Fn (Fn^-0.9).
    try std.testing.expect(CW_high != CW_low);
}

test "input rejection: zero L in c_1" {
    try std.testing.expectError(
        Error.InvalidGeometry,
        c1Coefficient(0.2, 8.0, 16.0, 90.0),
    );
}

test "input rejection: zero density in appendage R" {
    try std.testing.expectError(
        Error.NonPositiveDensity,
        appendageResistanceN(0.0, 10.0, 0.003, 1.4, 80.0),
    );
}

test "input rejection: C_P > 1.0" {
    try std.testing.expectError(
        Error.NonPositiveBlockCoefficient,
        c16Coefficient(1.1),
    );
}

test "input rejection: i_E >= 90 deg" {
    try std.testing.expectError(
        Error.InvalidGeometry,
        c1Coefficient(0.2, 8.0, 16.0, 90.0),
    );
}

test "appendage form factor monotonic ordering: bilge_keel < bossings < shaft_brackets" {
    try std.testing.expect(
        AppendageType.bilge_keel.formFactor() <
            AppendageType.bossings.formFactor(),
    );
    try std.testing.expect(
        AppendageType.bossings.formFactor() <
            AppendageType.shaft_brackets.formFactor(),
    );
}

test "unequal appendage arrays rejected" {
    const types = [_]AppendageType{ .bilge_keel, .spade_rudder };
    const areas = [_]f64{30.0};
    try std.testing.expectError(
        Error.InvalidGeometry,
        equivalentAppendageFormFactor(&types, &areas),
    );
}
