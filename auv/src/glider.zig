const std = @import("std");

pub const Error = error{
    NonPositiveBuoyancy,
    InvalidLD,
    InvalidGlideAngle,
};

/// Glide angle gamma for a sea glider with lift-to-drag ratio L/D
/// in steady descent / ascent at constant speed:
///   tan(gamma) = 1 / (L/D).
pub fn glideAngleRad(LD: f64) Error!f64 {
    if (!(LD > 0)) return Error.InvalidLD;
    return std.math.atan(1.0 / LD);
}

/// Forward (horizontal) speed of a glider:
///   V_h = V_total * cos(gamma)
/// where V_total^2 = 2 * delta_B * g * V_displaced / (rho * S * C_D).
/// The kernel returns V_total in the simplest form when given the
/// net-buoyancy work term directly.
pub fn glideSpeedMPerS(
    net_buoyancy_n: f64,
    drag_coefficient: f64,
    rho_kg_per_m3: f64,
    S_w_m2: f64,
) Error!f64 {
    if (!(net_buoyancy_n > 0)) return Error.NonPositiveBuoyancy;
    if (!(drag_coefficient > 0)) return Error.InvalidLD;
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveBuoyancy;
    if (!(S_w_m2 > 0)) return Error.NonPositiveBuoyancy;
    return @sqrt(2.0 * net_buoyancy_n / (rho_kg_per_m3 * drag_coefficient * S_w_m2));
}

/// Horizontal range per glide leg of vertical excursion `delta_z`:
///   range_h = delta_z * (L/D).
pub fn horizontalRangePerLegM(delta_z_m: f64, LD: f64) Error!f64 {
    if (!(delta_z_m > 0)) return Error.InvalidGlideAngle;
    if (!(LD > 0)) return Error.InvalidLD;
    return delta_z_m * LD;
}

/// Vertical descent / ascent rate from V_total and glide angle:
///   V_z = V_total * sin(gamma).
pub fn verticalRateMPerS(V_total_mps: f64, gamma_rad: f64) Error!f64 {
    if (!(V_total_mps > 0)) return Error.NonPositiveBuoyancy;
    if (!(gamma_rad >= 0 and gamma_rad <= std.math.pi / 2.0)) return Error.InvalidGlideAngle;
    return V_total_mps * @sin(gamma_rad);
}

test "glide angle at L/D = 30 is small (~ 1.91 deg)" {
    const gamma = try glideAngleRad(30.0);
    const deg = 180.0 / std.math.pi;
    try std.testing.expectApproxEqAbs(@as(f64, 1.91), gamma * deg, 0.05);
}

test "glide angle at L/D = 1 is pi/4" {
    const gamma = try glideAngleRad(1.0);
    try std.testing.expectApproxEqAbs(std.math.pi / 4.0, gamma, 1e-12);
}

test "glide angle decreases with L/D" {
    const g_1 = try glideAngleRad(1.0);
    const g_10 = try glideAngleRad(10.0);
    const g_30 = try glideAngleRad(30.0);
    try std.testing.expect(g_30 < g_10);
    try std.testing.expect(g_10 < g_1);
}

test "glide speed: 10 N net, C_d = 0.5, rho = 1025, S = 0.5 m^2" {
    const V = try glideSpeedMPerS(10.0, 0.5, 1025.0, 0.5);
    const expected = @sqrt(@as(f64, 2.0 * 10.0 / (1025.0 * 0.5 * 0.5)));
    try std.testing.expectApproxEqAbs(expected, V, 1e-9);
}

test "glide speed scales with sqrt(net buoyancy)" {
    const V1 = try glideSpeedMPerS(10.0, 0.5, 1025.0, 0.5);
    const V2 = try glideSpeedMPerS(40.0, 0.5, 1025.0, 0.5);
    try std.testing.expectApproxEqAbs(2.0, V2 / V1, 1e-9);
}

test "horizontal range per leg: 200 m descent at L/D=30 = 6 km" {
    const r = try horizontalRangePerLegM(200.0, 30.0);
    try std.testing.expectApproxEqAbs(@as(f64, 6000.0), r, 1e-9);
}

test "vertical rate at V=0.3 m/s, gamma=pi/6 = 0.15 m/s" {
    const v = try verticalRateMPerS(0.3, std.math.pi / 6.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.15), v, 1e-9);
}

test "vertical rate at gamma = 0 is zero (level flight)" {
    const v = try verticalRateMPerS(0.3, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), v, 1e-12);
}

test "vertical rate at gamma = pi/2 equals V_total" {
    const v = try verticalRateMPerS(0.3, std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.3), v, 1e-12);
}

test "input rejection: zero L/D" {
    try std.testing.expectError(Error.InvalidLD, glideAngleRad(0.0));
}

test "input rejection: zero net buoyancy" {
    try std.testing.expectError(
        Error.NonPositiveBuoyancy,
        glideSpeedMPerS(0.0, 0.5, 1025.0, 0.5),
    );
}

test "input rejection: gamma > pi/2" {
    try std.testing.expectError(
        Error.InvalidGlideAngle,
        verticalRateMPerS(0.3, 2.0),
    );
}
