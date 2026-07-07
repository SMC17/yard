const std = @import("std");

pub const Error = error{
    NonPositiveArea,
    InvalidEfficiency,
    NonPositiveInsolation,
    NonPositiveCapacity,
    NonPositiveLoad,
};

/// Average solar power generation:
///   P = A_solar * I_avg * eta_pv.
pub fn solarPowerW(
    A_solar_m2: f64,
    I_avg_w_per_m2: f64,
    eta_pv: f64,
) Error!f64 {
    if (!(A_solar_m2 > 0)) return Error.NonPositiveArea;
    if (!(I_avg_w_per_m2 > 0)) return Error.NonPositiveInsolation;
    if (!(eta_pv > 0 and eta_pv <= 1.0)) return Error.InvalidEfficiency;
    return A_solar_m2 * I_avg_w_per_m2 * eta_pv;
}

/// Daily energy: P [W] * 24 h = E [Wh].
pub fn dailyEnergyWh(P_avg_w: f64) Error!f64 {
    if (!(P_avg_w >= 0)) return Error.NonPositiveLoad;
    return P_avg_w * 24.0;
}

/// Battery autonomy [days] = capacity / daily load.
pub fn batteryAutonomyDays(
    capacity_wh: f64,
    daily_load_wh: f64,
) Error!f64 {
    if (!(capacity_wh > 0)) return Error.NonPositiveCapacity;
    if (!(daily_load_wh > 0)) return Error.NonPositiveLoad;
    return capacity_wh / daily_load_wh;
}

/// Net daily energy = solar production - daily load.
pub fn netDailyEnergyWh(
    solar_power_w: f64,
    daily_load_wh: f64,
) Error!f64 {
    const E_solar = try dailyEnergyWh(solar_power_w);
    if (!(daily_load_wh >= 0)) return Error.NonPositiveLoad;
    return E_solar - daily_load_wh;
}

/// Typical insolation maps [W/m^2] for selected oceanographic
/// regions (annual average).
pub const I_avg_north_atlantic: f64 = 200.0;
pub const I_avg_mediterranean: f64 = 280.0;
pub const I_avg_equatorial: f64 = 350.0;
pub const I_avg_arctic_summer: f64 = 180.0;

/// Typical monocrystalline-silicon PV efficiency.
pub const eta_pv_si_default: f64 = 0.22;

test "solar power at A=2, I=200, eta=0.22 = 88 W" {
    const P = try solarPowerW(2.0, 200.0, 0.22);
    try std.testing.expectApproxEqAbs(@as(f64, 88.0), P, 1e-9);
}

test "solar power scales linearly with A" {
    const P1 = try solarPowerW(1.0, 200.0, 0.22);
    const P2 = try solarPowerW(2.0, 200.0, 0.22);
    try std.testing.expectApproxEqAbs(2.0 * P1, P2, 1e-9);
}

test "solar power scales linearly with I" {
    const P1 = try solarPowerW(2.0, 200.0, 0.22);
    const P2 = try solarPowerW(2.0, 400.0, 0.22);
    try std.testing.expectApproxEqAbs(2.0 * P1, P2, 1e-9);
}

test "daily energy 88 W * 24 = 2112 Wh" {
    const E = try dailyEnergyWh(88.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2112.0), E, 1e-9);
}

test "battery autonomy: 1000 Wh / 200 Wh/day = 5 days" {
    const d = try batteryAutonomyDays(1000.0, 200.0);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), d, 1e-9);
}

test "battery autonomy scales inversely with daily load" {
    const d1 = try batteryAutonomyDays(1000.0, 100.0);
    const d2 = try batteryAutonomyDays(1000.0, 200.0);
    try std.testing.expectApproxEqAbs(0.5 * d1, d2, 1e-9);
}

test "net daily energy positive when production exceeds load" {
    const net = try netDailyEnergyWh(88.0, 2000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2112.0 - 2000.0), net, 1e-9);
}

test "net daily energy negative when load exceeds production" {
    const net = try netDailyEnergyWh(88.0, 3000.0);
    try std.testing.expect(net < 0);
}

test "insolation regional values: equator > Mediterranean > Atlantic > Arctic" {
    try std.testing.expect(I_avg_equatorial > I_avg_mediterranean);
    try std.testing.expect(I_avg_mediterranean > I_avg_north_atlantic);
    try std.testing.expect(I_avg_north_atlantic > I_avg_arctic_summer);
}

test "eta_pv_si_default 22 %" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.22), eta_pv_si_default, 1e-12);
}

test "input rejection: zero area" {
    try std.testing.expectError(Error.NonPositiveArea, solarPowerW(0.0, 200.0, 0.22));
}

test "input rejection: eta > 1" {
    try std.testing.expectError(Error.InvalidEfficiency, solarPowerW(2.0, 200.0, 1.2));
}

test "input rejection: zero capacity" {
    try std.testing.expectError(Error.NonPositiveCapacity, batteryAutonomyDays(0.0, 200.0));
}
