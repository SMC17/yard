const std = @import("std");

pub const Error = error{
    NonPositiveDensity,
    NonPositiveDimension,
    NonPositiveSpeed,
    InvalidApparentAngle,
};

/// Projected area of the rotor (diameter * height) [m^2].
pub fn projectedAreaM2(D_m: f64, h_m: f64) Error!f64 {
    if (!(D_m > 0)) return Error.NonPositiveDimension;
    if (!(h_m > 0)) return Error.NonPositiveDimension;
    return D_m * h_m;
}

/// Lift force on a Flettner rotor:
///   L = 0.5 rho V^2 D h C_L.
pub fn liftN(
    rho_kg_per_m3: f64,
    V_mps: f64,
    D_m: f64,
    h_m: f64,
    C_L: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(D_m > 0)) return Error.NonPositiveDimension;
    if (!(h_m > 0)) return Error.NonPositiveDimension;
    return 0.5 * rho_kg_per_m3 * V_mps * V_mps * D_m * h_m * C_L;
}

/// Drag force on a Flettner rotor:
///   D_force = 0.5 rho V^2 D h C_D.
pub fn dragN(
    rho_kg_per_m3: f64,
    V_mps: f64,
    D_m: f64,
    h_m: f64,
    C_D: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(D_m > 0)) return Error.NonPositiveDimension;
    if (!(h_m > 0)) return Error.NonPositiveDimension;
    return 0.5 * rho_kg_per_m3 * V_mps * V_mps * D_m * h_m * C_D;
}

/// Decomposition of rotor lift + drag into ship-body surge / sway:
///   theta = apparent-wind angle from the bow (0 = head, pi/2 = beam).
///   L is perpendicular to V_apparent, D is parallel.
///   X (surge) = L sin(theta) - D cos(theta)
///   Y (sway)  = -L cos(theta) - D sin(theta)
/// (For positive lift, the rotor pushes upwind side of the apparent
/// wind; the sign convention assumes the rotor spins in the
/// direction that produces a forward thrust component on a starboard
/// tack-equivalent.)
pub const BodyForce = struct { X_n: f64, Y_n: f64 };

pub fn decomposeBodyForce(L_n: f64, D_n: f64, theta_rad: f64) Error!BodyForce {
    if (!(theta_rad >= 0 and theta_rad <= 2.0 * std.math.pi)) return Error.InvalidApparentAngle;
    return .{
        .X_n = L_n * @sin(theta_rad) - D_n * @cos(theta_rad),
        .Y_n = -L_n * @cos(theta_rad) - D_n * @sin(theta_rad),
    };
}

test "projected area D x h" {
    const A = try projectedAreaM2(4.0, 24.0);
    try std.testing.expectApproxEqAbs(@as(f64, 96.0), A, 1e-12);
}

test "lift force at typical rotor: D=4, h=24, V=12, C_L=6" {
    const L = try liftN(1.225, 12.0, 4.0, 24.0, 6.0);
    // 0.5 * 1.225 * 144 * 96 * 6 = 50 803 N.
    const expected = 0.5 * 1.225 * 144.0 * 96.0 * 6.0;
    try std.testing.expectApproxEqAbs(expected, L, 1e-6);
}

test "drag force at same rotor with C_D = 1.5" {
    const D = try dragN(1.225, 12.0, 4.0, 24.0, 1.5);
    const expected = 0.5 * 1.225 * 144.0 * 96.0 * 1.5;
    try std.testing.expectApproxEqAbs(expected, D, 1e-6);
}

test "lift scales with V^2" {
    const L1 = try liftN(1.225, 6.0, 4.0, 24.0, 6.0);
    const L2 = try liftN(1.225, 12.0, 4.0, 24.0, 6.0);
    try std.testing.expectApproxEqAbs(4.0 * L1, L2, 1e-6);
}

test "decompose at theta = pi/2 (beam wind): pure surge" {
    const f = try decomposeBodyForce(1000.0, 100.0, std.math.pi / 2.0);
    // X = 1000 * 1 - 100 * 0 = 1000; Y = -1000 * 0 - 100 * 1 = -100.
    try std.testing.expectApproxEqAbs(@as(f64, 1000.0), f.X_n, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, -100.0), f.Y_n, 1e-9);
}

test "decompose at theta = 0 (head wind): no surge contribution from L, drag opposes" {
    const f = try decomposeBodyForce(1000.0, 100.0, 0.0);
    // X = 0 - 100 = -100 (drag holds ship back); Y = -1000.
    try std.testing.expectApproxEqAbs(@as(f64, -100.0), f.X_n, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, -1000.0), f.Y_n, 1e-9);
}

test "decompose magnitude preserved" {
    const f = try decomposeBodyForce(800.0, 150.0, 0.7);
    const mag = @sqrt(f.X_n * f.X_n + f.Y_n * f.Y_n);
    const expected = @sqrt(800.0 * 800.0 + 150.0 * 150.0);
    try std.testing.expectApproxEqAbs(expected, mag, 1e-6);
}

test "lift force scales linearly with rotor area" {
    const L1 = try liftN(1.225, 12.0, 4.0, 24.0, 6.0);
    const L2 = try liftN(1.225, 12.0, 8.0, 24.0, 6.0);
    try std.testing.expectApproxEqAbs(2.0 * L1, L2, 1e-6);
}

test "input rejection: zero density" {
    try std.testing.expectError(Error.NonPositiveDensity, liftN(0.0, 12.0, 4.0, 24.0, 6.0));
}

test "input rejection: theta out of range" {
    try std.testing.expectError(
        Error.InvalidApparentAngle,
        decomposeBodyForce(1000.0, 100.0, 7.0),
    );
}
