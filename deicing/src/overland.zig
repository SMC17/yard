const std = @import("std");

pub const Error = error{
    NonPositiveWindSpeed,
    TemperatureOutOfRange,
};

/// Salt-water freezing point [deg C].
pub const T_freeze_seawater_deg_c: f64 = -1.7;

/// Overland 1986 predictor index PR:
///   PR = V_wind * (T_freeze - T_air) / (1 + 0.4 (T_sea - T_freeze))
/// Returns 0 if (T_freeze - T_air) <= 0 (air too warm to ice).
pub fn predictorIndex(
    V_wind_mps: f64,
    T_air_deg_c: f64,
    T_sea_deg_c: f64,
) Error!f64 {
    if (!(V_wind_mps >= 0)) return Error.NonPositiveWindSpeed;
    if (!(T_air_deg_c > -100.0 and T_air_deg_c < 100.0)) return Error.TemperatureOutOfRange;
    if (!(T_sea_deg_c > -5.0 and T_sea_deg_c < 40.0)) return Error.TemperatureOutOfRange;
    if (!(T_freeze_seawater_deg_c - T_air_deg_c > 0)) return 0.0;
    return V_wind_mps * (T_freeze_seawater_deg_c - T_air_deg_c) /
        (1.0 + 0.4 * (T_sea_deg_c - T_freeze_seawater_deg_c));
}

pub const IcingClass = enum {
    none,
    light,
    moderate,
    heavy,
    extreme,
};

/// Overland 1986 classification map.
pub fn classifyByIndex(PR: f64) IcingClass {
    if (PR <= 0.0) return .none;
    if (PR <= 22.4) return .light;
    if (PR <= 53.3) return .moderate;
    if (PR <= 83.0) return .heavy;
    return .extreme;
}

/// Convenience composer: PR -> class.
pub fn classifyByConditions(
    V_wind_mps: f64,
    T_air_deg_c: f64,
    T_sea_deg_c: f64,
) Error!IcingClass {
    const PR = try predictorIndex(V_wind_mps, T_air_deg_c, T_sea_deg_c);
    return classifyByIndex(PR);
}

test "predictor zero when T_air > freezing point" {
    const PR = try predictorIndex(15.0, 5.0, 8.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), PR, 1e-12);
}

test "predictor closed form at V=15, T_air=-10, T_sea=5" {
    const PR = try predictorIndex(15.0, -10.0, 5.0);
    // (T_freeze - T_air) = -1.7 - (-10) = 8.3
    // (T_sea - T_freeze) = 5 - (-1.7) = 6.7
    // denom = 1 + 0.4 * 6.7 = 1 + 2.68 = 3.68
    // PR = 15 * 8.3 / 3.68 = 124.5 / 3.68 = 33.83
    const expected = 15.0 * 8.3 / (1.0 + 0.4 * 6.7);
    try std.testing.expectApproxEqAbs(expected, PR, 1e-9);
}

test "predictor scales linearly with wind speed" {
    const PR1 = try predictorIndex(10.0, -10.0, 5.0);
    const PR2 = try predictorIndex(20.0, -10.0, 5.0);
    try std.testing.expectApproxEqAbs(2.0 * PR1, PR2, 1e-9);
}

test "classify: PR = 0 -> none" {
    try std.testing.expectEqual(IcingClass.none, classifyByIndex(0.0));
}

test "classify: PR = 10 -> light" {
    try std.testing.expectEqual(IcingClass.light, classifyByIndex(10.0));
}

test "classify: PR = 22.4 -> light (boundary inclusive)" {
    try std.testing.expectEqual(IcingClass.light, classifyByIndex(22.4));
}

test "classify: PR = 30 -> moderate" {
    try std.testing.expectEqual(IcingClass.moderate, classifyByIndex(30.0));
}

test "classify: PR = 60 -> heavy" {
    try std.testing.expectEqual(IcingClass.heavy, classifyByIndex(60.0));
}

test "classify: PR = 90 -> extreme" {
    try std.testing.expectEqual(IcingClass.extreme, classifyByIndex(90.0));
}

test "classify composer reproduces V=15, T_air=-10, T_sea=5 case" {
    const cls = try classifyByConditions(15.0, -10.0, 5.0);
    // PR ~ 33.83 -> moderate.
    try std.testing.expectEqual(IcingClass.moderate, cls);
}

test "classify composer at warm air gives none" {
    const cls = try classifyByConditions(15.0, 5.0, 8.0);
    try std.testing.expectEqual(IcingClass.none, cls);
}

test "input rejection: negative wind speed" {
    try std.testing.expectError(Error.NonPositiveWindSpeed, predictorIndex(-1.0, -10.0, 5.0));
}

test "input rejection: extreme temperature" {
    try std.testing.expectError(Error.TemperatureOutOfRange, predictorIndex(15.0, -200.0, 5.0));
}
