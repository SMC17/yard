const std = @import("std");

pub const Error = error{
    NonPositiveThrust,
    AngleOutOfRange,
    NonPositiveSpeed,
    InvalidWakeFraction,
};

pub const Components = struct {
    /// Longitudinal force component aligned with the ship's surge axis [N].
    Tx_n: f64,
    /// Lateral force component along the sway axis [N].
    Ty_n: f64,
};

/// Resolve open-water thrust at steering angle theta into
/// (T_x, T_y) = T_OW (cos theta, sin theta). `theta_rad` is the
/// pod-shaft rotation about the vertical axis, range [-pi, +pi].
pub fn resolveSteeringForce(T_open_water_n: f64, theta_rad: f64) Error!Components {
    if (!(T_open_water_n >= 0)) return Error.NonPositiveThrust;
    if (!(theta_rad >= -std.math.pi and theta_rad <= std.math.pi)) {
        return Error.AngleOutOfRange;
    }
    return .{
        .Tx_n = T_open_water_n * @cos(theta_rad),
        .Ty_n = T_open_water_n * @sin(theta_rad),
    };
}

/// Effective advance velocity V_a = V_ship (1 - w_T).
pub fn advanceVelocity(V_ship_mps: f64, wake_fraction: f64) Error!f64 {
    if (!(V_ship_mps >= 0)) return Error.NonPositiveSpeed;
    if (!(wake_fraction < 1.0)) return Error.InvalidWakeFraction;
    return V_ship_mps * (1.0 - wake_fraction);
}

/// Side-force ratio T_y / T_x = tan(theta). Returned only for
/// |theta| < pi/2 to keep finite (the lateral-only regime at
/// theta = +/- pi/2 has infinite slope).
pub fn sideForceRatio(theta_rad: f64) Error!f64 {
    if (!(theta_rad > -std.math.pi / 2.0 and theta_rad < std.math.pi / 2.0)) {
        return Error.AngleOutOfRange;
    }
    return std.math.tan(theta_rad);
}

test "resolveSteeringForce at theta = 0 gives pure surge" {
    const c = try resolveSteeringForce(1000.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1000.0), c.Tx_n, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), c.Ty_n, 1e-9);
}

test "resolveSteeringForce at theta = pi/2 gives pure sway" {
    const c = try resolveSteeringForce(1000.0, std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), c.Tx_n, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 1000.0), c.Ty_n, 1e-9);
}

test "resolveSteeringForce at theta = pi gives reverse surge" {
    const c = try resolveSteeringForce(1000.0, std.math.pi);
    try std.testing.expectApproxEqAbs(@as(f64, -1000.0), c.Tx_n, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), c.Ty_n, 1e-9);
}

test "resolveSteeringForce magnitude preserves T_OW" {
    const T_OW: f64 = 1500.0;
    const c = try resolveSteeringForce(T_OW, 0.7);
    const mag = @sqrt(c.Tx_n * c.Tx_n + c.Ty_n * c.Ty_n);
    try std.testing.expectApproxEqAbs(T_OW, mag, 1e-9);
}

test "advance velocity: w = 0.2 reduces V_ship by 20 %" {
    const V_a = try advanceVelocity(10.0, 0.2);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), V_a, 1e-9);
}

test "sideForceRatio at theta = pi/4 is 1.0" {
    const r = try sideForceRatio(std.math.pi / 4.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), r, 1e-12);
}

test "sideForceRatio at theta = 0 is 0" {
    const r = try sideForceRatio(0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), r, 1e-12);
}

test "input rejection: negative thrust" {
    try std.testing.expectError(Error.NonPositiveThrust, resolveSteeringForce(-1.0, 0.0));
}

test "input rejection: angle out of range" {
    try std.testing.expectError(Error.AngleOutOfRange, resolveSteeringForce(1000.0, 4.0));
    try std.testing.expectError(Error.AngleOutOfRange, sideForceRatio(std.math.pi / 2.0));
}

test "input rejection: wake fraction >= 1" {
    try std.testing.expectError(Error.InvalidWakeFraction, advanceVelocity(10.0, 1.0));
}
