const std = @import("std");

pub const Error = error{
    NonPositiveDimension,
    InvalidGeometry,
};

/// Bulbous-bow transverse projected area at the FP, computed as an
/// ellipse approximation:
///   A_BT = (pi / 4) D_horizontal * D_vertical
/// where D_horizontal is the horizontal width of the bulb (typically
/// 0.7 - 1.4 m for an Aframax tanker) and D_vertical is the vertical
/// height (typically 0.5 - 1.2 of the bulb width).
pub fn ellipseAreaM2(D_h_m: f64, D_v_m: f64) Error!f64 {
    if (!(D_h_m > 0)) return Error.NonPositiveDimension;
    if (!(D_v_m > 0)) return Error.NonPositiveDimension;
    return std.math.pi * D_h_m * D_v_m / 4.0;
}

/// Bulb immersion factor P_B per Holtrop-Mennen 1984:
///   P_B = 0.56 sqrt(A_BT) / (T_F - 1.5 h_B)
/// where T_F is the forward draft and h_B is the bulb-tip CG height
/// above the keel. The fraction inside the parentheses must remain
/// positive for the bulb to be (partially) submerged with adequate
/// margin.
pub fn immersionFactorPB(
    A_BT_m2: f64,
    T_F_m: f64,
    h_B_m: f64,
) Error!f64 {
    if (!(A_BT_m2 > 0)) return Error.NonPositiveDimension;
    if (!(T_F_m > 0)) return Error.NonPositiveDimension;
    if (!(h_B_m >= 0)) return Error.NonPositiveDimension;
    if (!(T_F_m - 1.5 * h_B_m > 0)) return Error.InvalidGeometry;
    return 0.56 * @sqrt(A_BT_m2) / (T_F_m - 1.5 * h_B_m);
}

/// Bulb-tip Froude number Fn_i used in the bulb-resistance term:
///   Fn_i = V / sqrt(g (T_F - h_B - 0.25 sqrt(A_BT)) + 0.15 V^2)
pub fn bulbFroudeNumber(
    V_mps: f64,
    A_BT_m2: f64,
    T_F_m: f64,
    h_B_m: f64,
    g_mps2: f64,
) Error!f64 {
    if (!(V_mps > 0)) return Error.NonPositiveDimension;
    if (!(A_BT_m2 > 0)) return Error.NonPositiveDimension;
    if (!(T_F_m > h_B_m)) return Error.InvalidGeometry;
    const numerator = T_F_m - h_B_m - 0.25 * @sqrt(A_BT_m2);
    if (!(numerator > 0)) return Error.InvalidGeometry;
    return V_mps / @sqrt(g_mps2 * numerator + 0.15 * V_mps * V_mps);
}

test "ellipse area: D_h = D_v = 2 -> pi" {
    const A = try ellipseAreaM2(2.0, 2.0);
    try std.testing.expectApproxEqAbs(std.math.pi, A, 1e-12);
}

test "ellipse area scales linearly with both D_h and D_v" {
    const A_11 = try ellipseAreaM2(1.0, 1.0);
    const A_21 = try ellipseAreaM2(2.0, 1.0);
    const A_22 = try ellipseAreaM2(2.0, 2.0);
    try std.testing.expectApproxEqAbs(2.0 * A_11, A_21, 1e-12);
    try std.testing.expectApproxEqAbs(4.0 * A_11, A_22, 1e-12);
}

test "P_B at A_BT=2.56, T_F=8, h_B=4: 0.56 * 1.6 / (8 - 6) = 0.448" {
    const P_B = try immersionFactorPB(2.56, 8.0, 4.0);
    const expected = 0.56 * @sqrt(@as(f64, 2.56)) / (8.0 - 1.5 * 4.0);
    try std.testing.expectApproxEqAbs(expected, P_B, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.448), P_B, 1e-3);
}

test "P_B increases when bulb is deeper (lower h_B)" {
    const P_B_deep = try immersionFactorPB(2.56, 8.0, 3.0);
    const P_B_shallow = try immersionFactorPB(2.56, 8.0, 4.0);
    try std.testing.expect(P_B_deep < P_B_shallow);
}

test "P_B rejects T_F - 1.5 h_B <= 0" {
    try std.testing.expectError(Error.InvalidGeometry, immersionFactorPB(2.56, 5.0, 4.0));
}

test "bulb Froude number at typical conditions" {
    // V=8 m/s, A_BT=2.56, T_F=8, h_B=4: denom = sqrt(9.81 * (8 - 4 - 0.4) + 0.15 * 64)
    // = sqrt(9.81 * 3.6 + 9.6) = sqrt(35.32 + 9.6) = sqrt(44.92) = 6.7025.
    // Fn_i = 8 / 6.7025 = 1.194.
    const Fn_i = try bulbFroudeNumber(8.0, 2.56, 8.0, 4.0, 9.81);
    const num = 8.0 - 4.0 - 0.25 * @sqrt(@as(f64, 2.56));
    const expected = 8.0 / @sqrt(9.81 * num + 0.15 * 64.0);
    try std.testing.expectApproxEqAbs(expected, Fn_i, 1e-9);
}

test "bulb Froude number scales monotonically with V" {
    const Fn_lo = try bulbFroudeNumber(4.0, 2.56, 8.0, 4.0, 9.81);
    const Fn_hi = try bulbFroudeNumber(12.0, 2.56, 8.0, 4.0, 9.81);
    try std.testing.expect(Fn_hi > Fn_lo);
}

test "input rejection: zero V" {
    try std.testing.expectError(Error.NonPositiveDimension, bulbFroudeNumber(0.0, 2.56, 8.0, 4.0, 9.81));
}

test "input rejection: T_F <= h_B + 0.25 sqrt(A_BT)" {
    // T_F=4, A_BT=2.56, h_B=4: numerator = 4 - 4 - 0.4 = -0.4 < 0.
    try std.testing.expectError(Error.InvalidGeometry, bulbFroudeNumber(8.0, 2.56, 4.0, 4.0, 9.81));
}
