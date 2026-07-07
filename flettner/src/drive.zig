const std = @import("std");

pub const Error = error{
    NonPositiveDensity,
    NonPositiveDimension,
    NonPositiveSpeed,
    NegativeCoefficient,
};

/// Air-friction skin-coefficient for a smooth rotating cylinder
/// (Bilgen-Boulos 1973 fit). Typical C_f ~ 0.005-0.015 in the
/// operational range.
pub const C_f_default: f64 = 0.008;

/// Friction torque on the rotating cylinder:
///   T = 0.5 rho V^2 (pi D h R) C_f
/// Returns Nm. This is a simplified envelope; detailed CFD shows
/// torque rises with spin ratio; the kernel uses the static-wind
/// dynamic-pressure proxy.
pub fn frictionTorqueNm(
    rho_kg_per_m3: f64,
    V_mps: f64,
    D_m: f64,
    h_m: f64,
    R_m: f64,
    C_f: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(D_m > 0)) return Error.NonPositiveDimension;
    if (!(h_m > 0)) return Error.NonPositiveDimension;
    if (!(R_m > 0)) return Error.NonPositiveDimension;
    if (!(C_f >= 0)) return Error.NegativeCoefficient;
    return 0.5 * rho_kg_per_m3 * V_mps * V_mps * std.math.pi * D_m * h_m * R_m * C_f;
}

/// Electric drive power [W] = friction torque * omega.
pub fn drivePowerW(T_friction_nm: f64, omega_rps: f64) Error!f64 {
    if (!(omega_rps > 0)) return Error.NonPositiveSpeed;
    if (!(T_friction_nm >= 0)) return Error.NegativeCoefficient;
    return T_friction_nm * omega_rps;
}

/// Net propulsive power = thrust_x * V_ship - P_drive.
/// Caller supplies the X (surge) component of rotor force from
/// `rotor.decomposeBodyForce` and the ship speed through water.
pub fn netPropulsivePowerW(
    thrust_x_n: f64,
    V_ship_mps: f64,
    P_drive_w: f64,
) f64 {
    return thrust_x_n * V_ship_mps - P_drive_w;
}

test "friction torque closed form at typical rotor" {
    // rho=1.225, V=12, D=4, h=24, R=2, C_f = 0.008.
    // T = 0.5 * 1.225 * 144 * pi * 4 * 24 * 2 * 0.008
    //   = 88.2 * pi * 192 * 0.008 * 2 = 88.2 * pi * 3.072
    // Manual: 0.5 * 1.225 * 144 * pi * 4 * 24 * 2 * 0.008.
    const T = try frictionTorqueNm(1.225, 12.0, 4.0, 24.0, 2.0, 0.008);
    const expected = 0.5 * 1.225 * 144.0 * std.math.pi * 4.0 * 24.0 * 2.0 * 0.008;
    try std.testing.expectApproxEqAbs(expected, T, 1e-6);
}

test "friction torque scales linearly with C_f" {
    const T1 = try frictionTorqueNm(1.225, 12.0, 4.0, 24.0, 2.0, 0.008);
    const T2 = try frictionTorqueNm(1.225, 12.0, 4.0, 24.0, 2.0, 0.016);
    try std.testing.expectApproxEqAbs(2.0 * T1, T2, 1e-6);
}

test "friction torque scales with V^2" {
    const T1 = try frictionTorqueNm(1.225, 6.0, 4.0, 24.0, 2.0, 0.008);
    const T2 = try frictionTorqueNm(1.225, 12.0, 4.0, 24.0, 2.0, 0.008);
    try std.testing.expectApproxEqAbs(4.0 * T1, T2, 1e-6);
}

test "drive power: T = 1000 Nm, omega = 10 rad/s = 10 kW" {
    const P = try drivePowerW(1000.0, 10.0);
    try std.testing.expectApproxEqAbs(@as(f64, 10_000.0), P, 1e-9);
}

test "drive power scales linearly with omega" {
    const P1 = try drivePowerW(1000.0, 5.0);
    const P2 = try drivePowerW(1000.0, 10.0);
    try std.testing.expectApproxEqAbs(2.0 * P1, P2, 1e-9);
}

test "net propulsive power: 50 kN thrust at 8 m/s minus 30 kW drive = 370 kW" {
    const P_net = netPropulsivePowerW(50_000.0, 8.0, 30_000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 370_000.0), P_net, 1e-9);
}

test "net propulsive power can be negative if drive exceeds thrust contribution" {
    const P_net = netPropulsivePowerW(1000.0, 8.0, 30_000.0);
    try std.testing.expect(P_net < 0);
}

test "C_f_default reasonable value" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.008), C_f_default, 1e-12);
}

test "input rejection: zero V" {
    try std.testing.expectError(Error.NonPositiveSpeed, frictionTorqueNm(1.225, 0.0, 4.0, 24.0, 2.0, 0.008));
}

test "input rejection: negative C_f" {
    try std.testing.expectError(Error.NegativeCoefficient, frictionTorqueNm(1.225, 12.0, 4.0, 24.0, 2.0, -0.001));
}

test "input rejection: zero omega in drive power" {
    try std.testing.expectError(Error.NonPositiveSpeed, drivePowerW(1000.0, 0.0));
}
