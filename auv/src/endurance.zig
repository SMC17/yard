const std = @import("std");

pub const Error = error{
    NonPositiveCapacity,
    NonPositiveLoad,
    NonPositiveSpeed,
    InvalidEfficiency,
};

/// Propulsion power required to overcome drag:
///   P_prop = D * V / eta_p.
pub fn propulsionPowerW(
    D_n: f64,
    V_mps: f64,
    eta_propulsive: f64,
) Error!f64 {
    if (!(D_n > 0)) return Error.NonPositiveLoad;
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(eta_propulsive > 0 and eta_propulsive <= 1.0)) return Error.InvalidEfficiency;
    return D_n * V_mps / eta_propulsive;
}

/// Endurance from battery capacity:
///   t_endurance = E_battery / (P_prop + P_hotel).
pub fn enduranceHr(
    E_battery_wh: f64,
    P_prop_w: f64,
    P_hotel_w: f64,
) Error!f64 {
    if (!(E_battery_wh > 0)) return Error.NonPositiveCapacity;
    if (!(P_prop_w >= 0)) return Error.NonPositiveLoad;
    if (!(P_hotel_w >= 0)) return Error.NonPositiveLoad;
    const total = P_prop_w + P_hotel_w;
    if (total <= 0) return Error.NonPositiveLoad;
    return E_battery_wh / total;
}

/// Range: V * endurance.
pub fn rangeKm(V_mps: f64, t_endurance_hr: f64) Error!f64 {
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(t_endurance_hr > 0)) return Error.NonPositiveCapacity;
    return V_mps * t_endurance_hr * 3.6;
}

/// Optimal cruise speed: minimum specific energy
///   E_per_km = (P_prop + P_hotel) / (V * 3.6)
/// At cruise the drag-power dominator P_prop ~ V^3 makes E_per_km
/// scale as V^2 - hotel_load_term / V, with the minimum at the
/// inflection. The kernel returns
///   V_opt = (P_hotel / (rho S C_d))^(1/3).
pub fn optimalCruiseSpeedMPerS(
    P_hotel_w: f64,
    rho_kg_per_m3: f64,
    S_w_m2: f64,
    C_d_total: f64,
) Error!f64 {
    if (!(P_hotel_w > 0)) return Error.NonPositiveLoad;
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveLoad;
    if (!(S_w_m2 > 0)) return Error.NonPositiveLoad;
    if (!(C_d_total > 0)) return Error.NonPositiveLoad;
    return std.math.cbrt(P_hotel_w / (rho_kg_per_m3 * S_w_m2 * C_d_total));
}

test "propulsion power: D=50 N, V=1.5 m/s, eta=0.6 = 125 W" {
    const P = try propulsionPowerW(50.0, 1.5, 0.6);
    try std.testing.expectApproxEqAbs(@as(f64, 125.0), P, 1e-9);
}

test "propulsion power scales linearly with D" {
    const P1 = try propulsionPowerW(50.0, 1.5, 0.6);
    const P2 = try propulsionPowerW(100.0, 1.5, 0.6);
    try std.testing.expectApproxEqAbs(2.0 * P1, P2, 1e-9);
}

test "propulsion power inversely proportional to eta" {
    const P1 = try propulsionPowerW(50.0, 1.5, 0.6);
    const P2 = try propulsionPowerW(50.0, 1.5, 0.3);
    try std.testing.expectApproxEqAbs(2.0 * P1, P2, 1e-9);
}

test "endurance: 5000 Wh / (125 W prop + 25 W hotel) = 33.3 hr" {
    const t = try enduranceHr(5000.0, 125.0, 25.0);
    try std.testing.expectApproxEqAbs(@as(f64, 5000.0 / 150.0), t, 1e-9);
}

test "endurance scales linearly with capacity" {
    const t1 = try enduranceHr(5000.0, 125.0, 25.0);
    const t2 = try enduranceHr(10000.0, 125.0, 25.0);
    try std.testing.expectApproxEqAbs(2.0, t2 / t1, 1e-9);
}

test "range at V=1.5 m/s, t=33.3 hr = 180 km" {
    const r = try rangeKm(1.5, 33.333);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5 * 33.333 * 3.6), r, 1e-3);
}

test "range scales linearly with V at fixed endurance" {
    const r1 = try rangeKm(1.0, 30.0);
    const r2 = try rangeKm(2.0, 30.0);
    try std.testing.expectApproxEqAbs(2.0, r2 / r1, 1e-9);
}

test "optimal cruise speed: closed form" {
    const V_opt = try optimalCruiseSpeedMPerS(25.0, 1025.0, 5.0, 0.004);
    const expected = std.math.cbrt(@as(f64, 25.0 / (1025.0 * 5.0 * 0.004)));
    try std.testing.expectApproxEqAbs(expected, V_opt, 1e-9);
}

test "optimal cruise scales with cube-root of hotel power" {
    const V1 = try optimalCruiseSpeedMPerS(8.0, 1025.0, 5.0, 0.004);
    const V2 = try optimalCruiseSpeedMPerS(64.0, 1025.0, 5.0, 0.004);
    try std.testing.expectApproxEqAbs(2.0, V2 / V1, 1e-9);
}

test "input rejection: eta_propulsive > 1" {
    try std.testing.expectError(
        Error.InvalidEfficiency,
        propulsionPowerW(50.0, 1.5, 1.2),
    );
}

test "input rejection: zero battery" {
    try std.testing.expectError(
        Error.NonPositiveCapacity,
        enduranceHr(0.0, 125.0, 25.0),
    );
}

test "input rejection: zero total power" {
    try std.testing.expectError(Error.NonPositiveLoad, enduranceHr(5000.0, 0.0, 0.0));
}
