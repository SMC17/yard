const std = @import("std");

pub const Error = error{
    NonPositiveDensity,
    NonPositiveSpeed,
    NonPositiveArea,
    NonPositiveLength,
    InvalidApparentAngle,
};

/// Standard sea-level air density [kg/m^3].
pub const rho_air_standard: f64 = 1.225;

pub const ShipType = enum {
    /// Modern container ship.
    Container,
    /// VLCC / oil tanker.
    Tanker,
    /// General cargo / bulk carrier.
    Bulk,
    /// Passenger ferry / cruise ship.
    Passenger,
    /// Generic with sinusoidal symmetric coefficients.
    Generic,
};

/// Peak wind-force coefficient C_X_max per Blendermann 1996 ship-
/// type catalogue. The kernel uses a single-mode `sin(eps)` shape
/// for C_Y, `cos(eps)` for C_X, and `sin(2 eps)` for C_N as a first-
/// order approximation; ship-type values calibrate the peak.
pub fn peakCoefficients(stype: ShipType) struct { CX: f64, CY: f64, CN: f64 } {
    return switch (stype) {
        .Container => .{ .CX = 0.55, .CY = 0.85, .CN = 0.13 },
        .Tanker => .{ .CX = 0.45, .CY = 0.70, .CN = 0.10 },
        .Bulk => .{ .CX = 0.50, .CY = 0.80, .CN = 0.11 },
        .Passenger => .{ .CX = 0.65, .CY = 0.95, .CN = 0.15 },
        .Generic => .{ .CX = 0.55, .CY = 0.80, .CN = 0.12 },
    };
}

/// Longitudinal wind-force coefficient:
///   C_X(eps) = C_X_max * cos(eps).
pub fn longitudinalCoefficient(eps_rad: f64, stype: ShipType) Error!f64 {
    if (!(eps_rad >= -std.math.pi and eps_rad <= std.math.pi)) {
        return Error.InvalidApparentAngle;
    }
    return peakCoefficients(stype).CX * @cos(eps_rad);
}

/// Lateral wind-force coefficient:
///   C_Y(eps) = C_Y_max * sin(eps).
pub fn lateralCoefficient(eps_rad: f64, stype: ShipType) Error!f64 {
    if (!(eps_rad >= -std.math.pi and eps_rad <= std.math.pi)) {
        return Error.InvalidApparentAngle;
    }
    return peakCoefficients(stype).CY * @sin(eps_rad);
}

/// Yaw-moment coefficient:
///   C_N(eps) = C_N_max * sin(2 eps).
pub fn yawMomentCoefficient(eps_rad: f64, stype: ShipType) Error!f64 {
    if (!(eps_rad >= -std.math.pi and eps_rad <= std.math.pi)) {
        return Error.InvalidApparentAngle;
    }
    return peakCoefficients(stype).CN * @sin(2.0 * eps_rad);
}

/// Longitudinal wind force:
///   X = 0.5 rho V^2 A_L C_X(eps).
pub fn longitudinalForceN(
    rho_kg_per_m3: f64,
    V_mps: f64,
    A_L_m2: f64,
    eps_rad: f64,
    stype: ShipType,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(A_L_m2 > 0)) return Error.NonPositiveArea;
    const C_X = try longitudinalCoefficient(eps_rad, stype);
    return 0.5 * rho_kg_per_m3 * V_mps * V_mps * A_L_m2 * C_X;
}

/// Lateral wind force:
///   Y = 0.5 rho V^2 A_T C_Y(eps).
pub fn lateralForceN(
    rho_kg_per_m3: f64,
    V_mps: f64,
    A_T_m2: f64,
    eps_rad: f64,
    stype: ShipType,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(A_T_m2 > 0)) return Error.NonPositiveArea;
    const C_Y = try lateralCoefficient(eps_rad, stype);
    return 0.5 * rho_kg_per_m3 * V_mps * V_mps * A_T_m2 * C_Y;
}

/// Yaw moment:
///   N = 0.5 rho V^2 A_L L_OA C_N(eps).
pub fn yawMomentNm(
    rho_kg_per_m3: f64,
    V_mps: f64,
    A_L_m2: f64,
    L_OA_m: f64,
    eps_rad: f64,
    stype: ShipType,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(A_L_m2 > 0)) return Error.NonPositiveArea;
    if (!(L_OA_m > 0)) return Error.NonPositiveLength;
    const C_N = try yawMomentCoefficient(eps_rad, stype);
    return 0.5 * rho_kg_per_m3 * V_mps * V_mps * A_L_m2 * L_OA_m * C_N;
}

test "head wind eps=0: pure surge force, no sway, no yaw" {
    const X = try longitudinalForceN(rho_air_standard, 20.0, 1000.0, 0.0, .Container);
    const Y = try lateralForceN(rho_air_standard, 20.0, 500.0, 0.0, .Container);
    const N = try yawMomentNm(rho_air_standard, 20.0, 1000.0, 200.0, 0.0, .Container);
    try std.testing.expect(X > 0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), Y, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), N, 1e-9);
}

test "beam wind eps=pi/2: pure sway force, no surge" {
    const X = try longitudinalForceN(rho_air_standard, 20.0, 1000.0, std.math.pi / 2.0, .Container);
    const Y = try lateralForceN(rho_air_standard, 20.0, 500.0, std.math.pi / 2.0, .Container);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), X, 1e-9);
    try std.testing.expect(Y > 0);
}

test "yaw moment max at eps=pi/4" {
    const N_45 = try yawMomentCoefficient(std.math.pi / 4.0, .Container);
    const N_22 = try yawMomentCoefficient(std.math.pi / 8.0, .Container);
    const N_67 = try yawMomentCoefficient(3.0 * std.math.pi / 8.0, .Container);
    try std.testing.expect(N_45 > N_22);
    try std.testing.expect(N_45 > N_67);
}

test "force scales with V^2" {
    const X1 = try longitudinalForceN(rho_air_standard, 10.0, 1000.0, 0.0, .Container);
    const X2 = try longitudinalForceN(rho_air_standard, 20.0, 1000.0, 0.0, .Container);
    try std.testing.expectApproxEqAbs(4.0 * X1, X2, 1e-9);
}

test "tanker has lower C_Y peak than passenger ship" {
    const tk = peakCoefficients(.Tanker);
    const pass = peakCoefficients(.Passenger);
    try std.testing.expect(pass.CY > tk.CY);
}

test "container peak coefficients exact values" {
    const c = peakCoefficients(.Container);
    try std.testing.expectApproxEqAbs(@as(f64, 0.55), c.CX, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.85), c.CY, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.13), c.CN, 1e-12);
}

test "C_Y sign reverses with apparent angle" {
    const C_pos = try lateralCoefficient(std.math.pi / 2.0, .Container);
    const C_neg = try lateralCoefficient(-std.math.pi / 2.0, .Container);
    try std.testing.expectApproxEqAbs(C_pos, -C_neg, 1e-12);
}

test "stern wind eps = pi gives negative surge force" {
    const X = try longitudinalForceN(rho_air_standard, 20.0, 1000.0, std.math.pi, .Container);
    try std.testing.expect(X < 0);
}

test "yaw moment at eps = pi/2 is zero (sin(pi) = 0)" {
    const C = try yawMomentCoefficient(std.math.pi / 2.0, .Container);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), C, 1e-12);
}

test "input rejection: eps outside [-pi, pi]" {
    try std.testing.expectError(
        Error.InvalidApparentAngle,
        longitudinalCoefficient(4.0, .Container),
    );
}

test "input rejection: zero density" {
    try std.testing.expectError(
        Error.NonPositiveDensity,
        longitudinalForceN(0.0, 20.0, 1000.0, 0.0, .Container),
    );
}

test "input rejection: zero L_OA" {
    try std.testing.expectError(
        Error.NonPositiveLength,
        yawMomentNm(rho_air_standard, 20.0, 1000.0, 0.0, 0.5, .Container),
    );
}
