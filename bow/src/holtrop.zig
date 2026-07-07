const std = @import("std");

pub const Error = error{
    NonPositiveBeam,
    NonPositiveDraft,
    NonPositiveArea,
    NonPositiveCp,
    InvalidBowShape,
    NonPositiveLength,
};

/// Holtrop-Mennen 1984 c_3 coefficient: ratio of bulbous-bow
/// transverse area to (beam x mean draft x C_M correction). Per the
/// HM paper:
///   c_3 = 0.56 A_BT^1.5 / (B T (0.31 sqrt(A_BT) + T_F - h_B))
/// where T_F is the forward draft and h_B is the bulb-tip immersion
/// (height of the bulb-tip CG above the keel). A_BT is the transverse
/// projected area of the bulb at the FP measured at the still-water
/// level.
pub fn c3Coefficient(
    A_BT_m2: f64,
    B_m: f64,
    T_m: f64,
    T_F_m: f64,
    h_B_m: f64,
) Error!f64 {
    if (!(A_BT_m2 > 0)) return Error.NonPositiveArea;
    if (!(B_m > 0)) return Error.NonPositiveBeam;
    if (!(T_m > 0)) return Error.NonPositiveDraft;
    if (!(T_F_m > h_B_m)) return Error.NonPositiveDraft;
    const denom = B_m * T_m * (0.31 * @sqrt(A_BT_m2) + T_F_m - h_B_m);
    return 0.56 * std.math.pow(f64, A_BT_m2, 1.5) / denom;
}

/// Holtrop-Mennen c_2 coefficient (related to c_3 with the bulb-
/// immersion factor):
///   c_2 = exp(-1.89 sqrt(c_3))
/// captures the indirect bulb effect on wave-resistance coefficient.
pub fn c2Coefficient(c3: f64) f64 {
    return @exp(-1.89 * @sqrt(@abs(c3)));
}

/// Bow shape catalogue per Holtrop 1988 (extension of HM 1984).
pub const BowShape = enum {
    /// Pram with gondola.
    pram_with_gondola,
    /// V-shaped sections (no bulb).
    V_shaped_no_bulb,
    /// Normal section shape.
    normal,
    /// U-shaped sections.
    U_shaped,
    /// U-shaped with Hogner stern.
    U_shaped_with_hogner_stern,
};

/// Half-angle of entrance i_E correction coefficient c_4 per
/// Holtrop 1988 Table II values. Applied to the c_7 calculation.
pub fn c4Coefficient(shape: BowShape) f64 {
    return switch (shape) {
        .pram_with_gondola => -1.0,
        .V_shaped_no_bulb => -0.5,
        .normal => 0.0,
        .U_shaped => 0.5,
        .U_shaped_with_hogner_stern => 1.0,
    };
}

/// Holtrop-Mennen c_1 coefficient governing the wave-resistance
/// regression below Fn ~ 0.4:
///   c_1 = 2223105 c_7^3.78613 (T / B)^1.07961 (90 - i_E)^(-1.37565)
/// where i_E is the half-angle of entrance at the FP in degrees, and
/// c_7 is the breadth-to-length ratio:
///   c_7 = 0.229577 (B / L)^0.33333  if B/L < 0.11
///         B / L                      if 0.11 <= B/L < 0.25
///         0.5 - 0.0625 L / B         if B/L >= 0.25
pub fn c7Coefficient(B_m: f64, L_m: f64) Error!f64 {
    if (!(B_m > 0)) return Error.NonPositiveBeam;
    if (!(L_m > 0)) return Error.NonPositiveLength;
    const r = B_m / L_m;
    if (r < 0.11) return 0.229577 * std.math.pow(f64, r, 0.33333);
    if (r < 0.25) return r;
    return 0.5 - 0.0625 * L_m / B_m;
}

test "c_3: square A_BT = (B T / 10)^2 at typical bulb" {
    // For B=20, T=8, T_F=8, A_BT = 1.6^2 = 2.56, h_B = 4
    // denom = 20 * 8 * (0.31 * sqrt(2.56) + 8 - 4)
    //       = 160 * (0.31 * 1.6 + 4)
    //       = 160 * 4.496 = 719.36
    // c_3 = 0.56 * 2.56^1.5 / 719.36 = 0.56 * 4.0960 / 719.36 = 0.00319
    const c3 = try c3Coefficient(2.56, 20.0, 8.0, 8.0, 4.0);
    const denom = 20.0 * 8.0 * (0.31 * @sqrt(@as(f64, 2.56)) + 8.0 - 4.0);
    const expected = 0.56 * std.math.pow(f64, 2.56, 1.5) / denom;
    try std.testing.expectApproxEqAbs(expected, c3, 1e-9);
}

test "c_3 increases with A_BT^1.5" {
    const c3_1 = try c3Coefficient(2.56, 20.0, 8.0, 8.0, 4.0);
    const c3_2 = try c3Coefficient(10.24, 20.0, 8.0, 8.0, 4.0);
    // A_BT ratio is 4; A_BT^1.5 ratio is 8. Denom also changes a bit.
    try std.testing.expect(c3_2 > c3_1);
}

test "c_2: zero-bulb limit equals 1" {
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), c2Coefficient(0.0), 1e-12);
}

test "c_2 < 1 for any positive c_3" {
    try std.testing.expect(c2Coefficient(0.01) < 1.0);
    try std.testing.expect(c2Coefficient(0.1) < c2Coefficient(0.01));
}

test "c_2 at c_3 = 0.04: exp(-1.89 * 0.2) = exp(-0.378) = 0.685" {
    const c2 = c2Coefficient(0.04);
    const expected = @exp(@as(f64, -1.89 * 0.2));
    try std.testing.expectApproxEqAbs(expected, c2, 1e-9);
}

test "c_4 values across bow shapes" {
    try std.testing.expectApproxEqAbs(@as(f64, -1.0), c4Coefficient(.pram_with_gondola), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -0.5), c4Coefficient(.V_shaped_no_bulb), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), c4Coefficient(.normal), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), c4Coefficient(.U_shaped), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), c4Coefficient(.U_shaped_with_hogner_stern), 1e-12);
}

test "c_7: narrow ship B/L < 0.11 uses cube-root branch" {
    // B = 10, L = 100 -> B/L = 0.1 < 0.11.
    const c7 = try c7Coefficient(10.0, 100.0);
    const expected = 0.229577 * std.math.pow(f64, @as(f64, 0.1), 0.33333);
    try std.testing.expectApproxEqAbs(expected, c7, 1e-9);
}

test "c_7: typical ship 0.11 <= B/L < 0.25 returns B/L" {
    const c7 = try c7Coefficient(20.0, 100.0); // 0.2
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), c7, 1e-12);
}

test "c_7: wide ship B/L >= 0.25 uses 0.5 - 0.0625 L/B" {
    const c7 = try c7Coefficient(30.0, 100.0); // B/L = 0.3
    const expected = 0.5 - 0.0625 * 100.0 / 30.0;
    try std.testing.expectApproxEqAbs(expected, c7, 1e-12);
}

test "input rejection: zero A_BT" {
    try std.testing.expectError(Error.NonPositiveArea, c3Coefficient(0.0, 20.0, 8.0, 8.0, 4.0));
}

test "input rejection: T_F <= h_B (bulb above waterline)" {
    try std.testing.expectError(Error.NonPositiveDraft, c3Coefficient(2.56, 20.0, 8.0, 4.0, 5.0));
}

test "input rejection: zero L in c_7" {
    try std.testing.expectError(Error.NonPositiveLength, c7Coefficient(20.0, 0.0));
}
