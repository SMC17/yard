// IACS CSR-H Section 5 hull-girder vertical wave-bending moment +
// Section 6 hull-girder ultimate strength check.

const std = @import("std");

pub const Error = error{
    NonPositiveLength,
    NonPositiveBreadth,
    NonPositiveBlock,
    NonPositiveModulus,
    InvalidLoadCase,
};

/// IACS UR S11 / CSR-H Section 5.2.3 wave coefficient C:
///   C = 10.75 - ((300 - L) / 100)^1.5   for 90 <= L < 300
///     = 10.75                             for 300 <= L <= 350
///     = 10.75 - ((L - 350) / 150)^1.5     for L > 350
pub fn waveCoefficientC(L_m: f64) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (L_m < 90.0) return Error.NonPositiveLength;
    if (L_m < 300.0) {
        return 10.75 - std.math.pow(f64, (300.0 - L_m) / 100.0, 1.5);
    }
    if (L_m <= 350.0) return 10.75;
    return 10.75 - std.math.pow(f64, (L_m - 350.0) / 150.0, 1.5);
}

/// Hogging vertical wave bending moment per CSR-H 5.2:
///   M_wv_hog = 0.19 C L^2 B C_B [kNm].
pub fn waveBendingHoggingKNm(
    L_m: f64,
    B_m: f64,
    C_B: f64,
) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (!(B_m > 0)) return Error.NonPositiveBreadth;
    if (!(C_B > 0 and C_B <= 1.0)) return Error.NonPositiveBlock;
    const C = try waveCoefficientC(L_m);
    return 0.19 * C * L_m * L_m * B_m * C_B;
}

/// Sagging vertical wave bending moment per CSR-H 5.2:
///   M_wv_sag = -0.11 C L^2 B (C_B + 0.7) [kNm].
pub fn waveBendingSaggingKNm(
    L_m: f64,
    B_m: f64,
    C_B: f64,
) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (!(B_m > 0)) return Error.NonPositiveBreadth;
    if (!(C_B > 0 and C_B <= 1.0)) return Error.NonPositiveBlock;
    const C = try waveCoefficientC(L_m);
    return -0.11 * C * L_m * L_m * B_m * (C_B + 0.7);
}

/// Horizontal wave bending moment per CSR-H 5.3:
///   M_wh = 0.32 L C_B C L^2 B [kNm] (simplified).
pub fn waveBendingHorizontalKNm(
    L_m: f64,
    B_m: f64,
    C_B: f64,
) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (!(B_m > 0)) return Error.NonPositiveBreadth;
    if (!(C_B > 0 and C_B <= 1.0)) return Error.NonPositiveBlock;
    const C = try waveCoefficientC(L_m);
    return 0.32 * L_m * C_B * C * L_m * B_m / 100.0;
}

/// CSR-H Section 6 hull-girder ultimate vertical bending capacity
/// (simplified). Caller supplies the elastic section modulus Z [m^3]
/// and the partial safety factor:
///   M_U = gamma_M sigma_y Z.
pub fn ultimateMomentKNm(
    Z_m3: f64,
    sigma_y_mpa: f64,
    gamma_M: f64,
) Error!f64 {
    if (!(Z_m3 > 0)) return Error.NonPositiveModulus;
    if (!(sigma_y_mpa > 0)) return Error.NonPositiveModulus;
    if (!(gamma_M > 0)) return Error.NonPositiveModulus;
    // sigma_y in MPa -> kPa = sigma_y * 1000; Z in m^3 -> Z * 1000 mm^3? no.
    // M [kNm] = sigma [MPa] * Z [m^3] * 1000 (MPa = N/mm^2, M in Nmm).
    // Simplification: M_kNm = sigma_y_MPa * Z_m3 * 1e3.
    return gamma_M * sigma_y_mpa * Z_m3 * 1000.0;
}

pub const UltimateVerdict = enum { pass, fail };

/// Hull-girder ultimate strength check per CSR-H Section 6:
///   M_U >= gamma_S (M_sw + gamma_W M_wv).
pub fn ultimateStrengthVerdict(
    M_U_kNm: f64,
    M_sw_kNm: f64,
    M_wv_kNm: f64,
    gamma_S: f64,
    gamma_W: f64,
) Error!UltimateVerdict {
    if (!(M_U_kNm > 0)) return Error.NonPositiveModulus;
    if (!(gamma_S > 0)) return Error.NonPositiveModulus;
    if (!(gamma_W > 0)) return Error.NonPositiveModulus;
    const M_demand = gamma_S * (@abs(M_sw_kNm) + gamma_W * @abs(M_wv_kNm));
    if (M_U_kNm >= M_demand) return .pass;
    return .fail;
}

test "wave coefficient C at L=150 m" {
    const C = try waveCoefficientC(150.0);
    const expected = 10.75 - std.math.pow(f64, (300.0 - 150.0) / 100.0, 1.5);
    try std.testing.expectApproxEqAbs(expected, C, 1e-9);
}

test "wave coefficient C at L=300 m equals 10.75" {
    const C = try waveCoefficientC(300.0);
    try std.testing.expectApproxEqAbs(@as(f64, 10.75), C, 1e-12);
}

test "wave coefficient C at L=350 m equals 10.75" {
    const C = try waveCoefficientC(350.0);
    try std.testing.expectApproxEqAbs(@as(f64, 10.75), C, 1e-12);
}

test "wave coefficient C declines above 350 m" {
    const C_350 = try waveCoefficientC(350.0);
    const C_400 = try waveCoefficientC(400.0);
    try std.testing.expect(C_400 < C_350);
}

test "wave coefficient rejects L < 90" {
    try std.testing.expectError(Error.NonPositiveLength, waveCoefficientC(50.0));
}

test "hogging moment at L=200, B=32, C_B=0.85" {
    const M = try waveBendingHoggingKNm(200.0, 32.0, 0.85);
    const C = try waveCoefficientC(200.0);
    const expected = 0.19 * C * 40000.0 * 32.0 * 0.85;
    try std.testing.expectApproxEqAbs(expected, M, 1e-3);
}

test "sagging moment is negative" {
    const M = try waveBendingSaggingKNm(200.0, 32.0, 0.85);
    try std.testing.expect(M < 0);
}

test "hogging > 0; sagging magnitude similar order" {
    const M_h = try waveBendingHoggingKNm(200.0, 32.0, 0.85);
    const M_s = try waveBendingSaggingKNm(200.0, 32.0, 0.85);
    try std.testing.expect(M_h > 0);
    try std.testing.expect(@abs(M_s) > 0);
    // Sagging magnitude typically exceeds hogging for C_B < 1.
    try std.testing.expect(@abs(M_s) > M_h * 0.7);
}

test "horizontal moment positive" {
    const M = try waveBendingHorizontalKNm(200.0, 32.0, 0.85);
    try std.testing.expect(M > 0);
}

test "hogging scales with L^2" {
    const M1 = try waveBendingHoggingKNm(150.0, 30.0, 0.85);
    const M2 = try waveBendingHoggingKNm(200.0, 30.0, 0.85);
    // Direct L^2 scaling is contaminated by C(L); both L are in the
    // < 300 m regime so ratio is dominated by L^2 * C(L).
    const C1 = try waveCoefficientC(150.0);
    const C2 = try waveCoefficientC(200.0);
    const expected_ratio = (200.0 * 200.0 * C2) / (150.0 * 150.0 * C1);
    try std.testing.expectApproxEqAbs(expected_ratio, M2 / M1, 1e-6);
}

test "ultimate moment closed form" {
    const M_U = try ultimateMomentKNm(20.0, 355.0, 0.85);
    try std.testing.expectApproxEqAbs(@as(f64, 0.85 * 355.0 * 20.0 * 1000.0), M_U, 1.0);
}

test "ultimate moment scales linearly with Z, sigma_y" {
    const M1 = try ultimateMomentKNm(20.0, 355.0, 1.0);
    const M2 = try ultimateMomentKNm(40.0, 355.0, 1.0);
    try std.testing.expectApproxEqAbs(2.0 * M1, M2, 1.0);
    const M3 = try ultimateMomentKNm(20.0, 710.0, 1.0);
    try std.testing.expectApproxEqAbs(2.0 * M1, M3, 1.0);
}

test "ultimate verdict pass at high M_U" {
    const v = try ultimateStrengthVerdict(1.0e7, 1.0e6, 1.0e6, 1.0, 1.2);
    try std.testing.expectEqual(UltimateVerdict.pass, v);
}

test "ultimate verdict fail at low M_U" {
    const v = try ultimateStrengthVerdict(1.0e6, 5.0e6, 5.0e6, 1.0, 1.2);
    try std.testing.expectEqual(UltimateVerdict.fail, v);
}

test "ultimate verdict at exact threshold passes" {
    const M_demand = 1.0 * (1.0e6 + 1.2 * 1.0e6);
    const v = try ultimateStrengthVerdict(M_demand, 1.0e6, 1.0e6, 1.0, 1.2);
    try std.testing.expectEqual(UltimateVerdict.pass, v);
}

test "input rejection: C_B > 1" {
    try std.testing.expectError(Error.NonPositiveBlock, waveBendingHoggingKNm(200.0, 32.0, 1.1));
}

test "input rejection: zero Z in ultimate moment" {
    try std.testing.expectError(Error.NonPositiveModulus, ultimateMomentKNm(0.0, 355.0, 1.0));
}
