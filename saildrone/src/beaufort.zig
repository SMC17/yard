const std = @import("std");

pub const Error = error{
    InvalidBeaufort,
    NonPositiveArea,
    NonPositiveDensity,
    NonPositiveHeight,
};

/// Beaufort wind-scale typical wind speed [m/s] at scale `n` per
/// the WMO 1946 convention; midpoint of the published range.
pub fn beaufortWindSpeed(n: u8) Error!f64 {
    return switch (n) {
        0 => 0.15,
        1 => 1.0,
        2 => 2.5,
        3 => 4.5,
        4 => 7.0,
        5 => 9.5,
        6 => 12.5,
        7 => 15.5,
        8 => 19.0,
        9 => 22.5,
        10 => 26.5,
        11 => 30.5,
        12 => 34.0, // 32.7 m/s+ in WMO definition
        else => Error.InvalidBeaufort,
    };
}

/// Heeling moment under apparent wind on a sail of area A_s and
/// CG-above-waterline height h_sail:
///   M_h = 0.5 rho_air v^2 A_s C_L h_sail
/// (C_L ~ 1.2 close-hauled).
pub fn heelingMomentNm(
    rho_air_kg_per_m3: f64,
    v_wind_mps: f64,
    A_s_m2: f64,
    C_L: f64,
    h_sail_m: f64,
) Error!f64 {
    if (!(rho_air_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(v_wind_mps >= 0)) return Error.NonPositiveDensity;
    if (!(A_s_m2 > 0)) return Error.NonPositiveArea;
    if (!(C_L > 0)) return Error.NonPositiveArea;
    if (!(h_sail_m > 0)) return Error.NonPositiveHeight;
    return 0.5 * rho_air_kg_per_m3 * v_wind_mps * v_wind_mps * A_s_m2 * C_L * h_sail_m;
}

/// Default close-hauled wing-sail lift coefficient.
pub const C_L_close_hauled: f64 = 1.2;

/// Composer: heeling moment from Beaufort scale + sail geometry.
pub fn heelingMomentFromBeaufortNm(
    n: u8,
    A_s_m2: f64,
    h_sail_m: f64,
) Error!f64 {
    const v = try beaufortWindSpeed(n);
    return try heelingMomentNm(1.225, v, A_s_m2, C_L_close_hauled, h_sail_m);
}

test "Beaufort 0 returns 0.15 m/s" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.15), try beaufortWindSpeed(0), 1e-12);
}

test "Beaufort 12 returns 34 m/s" {
    try std.testing.expectApproxEqAbs(@as(f64, 34.0), try beaufortWindSpeed(12), 1e-12);
}

test "Beaufort scale monotone increasing" {
    var prev = try beaufortWindSpeed(0);
    var n: u8 = 1;
    while (n <= 12) : (n += 1) {
        const v = try beaufortWindSpeed(n);
        try std.testing.expect(v > prev);
        prev = v;
    }
}

test "Beaufort 13+ rejected" {
    try std.testing.expectError(Error.InvalidBeaufort, beaufortWindSpeed(13));
}

test "heeling moment at v = 10, A = 5, C_L = 1.2, h = 3" {
    const M = try heelingMomentNm(1.225, 10.0, 5.0, 1.2, 3.0);
    const expected = 0.5 * 1.225 * 100.0 * 5.0 * 1.2 * 3.0;
    try std.testing.expectApproxEqAbs(expected, M, 1e-6);
}

test "heeling moment scales with v^2" {
    const M_5 = try heelingMomentNm(1.225, 5.0, 5.0, 1.2, 3.0);
    const M_10 = try heelingMomentNm(1.225, 10.0, 5.0, 1.2, 3.0);
    try std.testing.expectApproxEqAbs(4.0 * M_5, M_10, 1e-6);
}

test "heeling moment scales linearly in area and height" {
    const M_base = try heelingMomentNm(1.225, 10.0, 5.0, 1.2, 3.0);
    const M_a = try heelingMomentNm(1.225, 10.0, 10.0, 1.2, 3.0);
    const M_h = try heelingMomentNm(1.225, 10.0, 5.0, 1.2, 6.0);
    try std.testing.expectApproxEqAbs(2.0 * M_base, M_a, 1e-6);
    try std.testing.expectApproxEqAbs(2.0 * M_base, M_h, 1e-6);
}

test "Beaufort composer at scale 6, A = 5, h = 3" {
    const M = try heelingMomentFromBeaufortNm(6, 5.0, 3.0);
    const v = try beaufortWindSpeed(6);
    const M_expected = try heelingMomentNm(1.225, v, 5.0, C_L_close_hauled, 3.0);
    try std.testing.expectApproxEqAbs(M_expected, M, 1e-12);
}

test "Beaufort 8 (gale) heeling moment exceeds Beaufort 4 (moderate)" {
    const M_4 = try heelingMomentFromBeaufortNm(4, 5.0, 3.0);
    const M_8 = try heelingMomentFromBeaufortNm(8, 5.0, 3.0);
    // v_8 / v_4 = 19 / 7 = 2.714, ratio squared = 7.36.
    try std.testing.expect(M_8 > 5.0 * M_4);
    try std.testing.expect(M_8 < 10.0 * M_4);
}

test "C_L_close_hauled default" {
    try std.testing.expectApproxEqAbs(@as(f64, 1.2), C_L_close_hauled, 1e-12);
}

test "input rejection: zero area" {
    try std.testing.expectError(Error.NonPositiveArea, heelingMomentNm(1.225, 10.0, 0.0, 1.2, 3.0));
}

test "input rejection: zero h_sail" {
    try std.testing.expectError(Error.NonPositiveHeight, heelingMomentNm(1.225, 10.0, 5.0, 1.2, 0.0));
}
