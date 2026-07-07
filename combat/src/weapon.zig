const std = @import("std");

pub const Error = error{
    NonPositiveMass,
    NonPositiveSpeed,
    NonPositiveDuration,
    NonPositiveArea,
    NonPositivePressure,
};

/// Naval-gun recoil impulse:
///   J = m_proj V_muzzle.
pub fn recoilImpulseNs(m_proj_kg: f64, V_muzzle_mps: f64) Error!f64 {
    if (!(m_proj_kg > 0)) return Error.NonPositiveMass;
    if (!(V_muzzle_mps > 0)) return Error.NonPositiveSpeed;
    return m_proj_kg * V_muzzle_mps;
}

/// Mean recoil force over charge time dt:
///   F = J / dt = m_proj V_muzzle / dt.
pub fn meanRecoilForceN(
    m_proj_kg: f64,
    V_muzzle_mps: f64,
    dt_charge_s: f64,
) Error!f64 {
    if (!(dt_charge_s > 0)) return Error.NonPositiveDuration;
    const J = try recoilImpulseNs(m_proj_kg, V_muzzle_mps);
    return J / dt_charge_s;
}

/// Muzzle energy:
///   E_muzzle = 0.5 m V_muzzle^2.
pub fn muzzleEnergyJ(m_proj_kg: f64, V_muzzle_mps: f64) Error!f64 {
    if (!(m_proj_kg > 0)) return Error.NonPositiveMass;
    if (!(V_muzzle_mps > 0)) return Error.NonPositiveSpeed;
    return 0.5 * m_proj_kg * V_muzzle_mps * V_muzzle_mps;
}

/// VLS canister axial thrust pressure on the deck during a missile
/// boost: F_thrust / A_deck_footprint.
pub fn vlsDeckPressurePa(
    thrust_n: f64,
    deck_footprint_m2: f64,
) Error!f64 {
    if (!(thrust_n > 0)) return Error.NonPositivePressure;
    if (!(deck_footprint_m2 > 0)) return Error.NonPositiveArea;
    return thrust_n / deck_footprint_m2;
}

/// Time of flight to peak in vacuum:
///   t_peak = V_muzzle * sin(theta) / g.
pub fn timeToApexS(
    V_muzzle_mps: f64,
    theta_rad: f64,
    g_mps2: f64,
) Error!f64 {
    if (!(V_muzzle_mps > 0)) return Error.NonPositiveSpeed;
    if (!(theta_rad >= 0 and theta_rad <= std.math.pi / 2.0)) {
        return Error.NonPositiveDuration;
    }
    return V_muzzle_mps * @sin(theta_rad) / g_mps2;
}

/// Maximum range of a vacuum-projectile fired at the optimal 45 deg:
///   R_max = V_muzzle^2 / g.
pub fn vacuumMaxRangeM(V_muzzle_mps: f64, g_mps2: f64) Error!f64 {
    if (!(V_muzzle_mps > 0)) return Error.NonPositiveSpeed;
    return V_muzzle_mps * V_muzzle_mps / g_mps2;
}

test "recoil impulse: 10 kg projectile at 900 m/s = 9000 Ns" {
    const J = try recoilImpulseNs(10.0, 900.0);
    try std.testing.expectApproxEqAbs(@as(f64, 9000.0), J, 1e-6);
}

test "recoil impulse scales linearly with mass and velocity" {
    const J1 = try recoilImpulseNs(10.0, 900.0);
    const J2 = try recoilImpulseNs(20.0, 900.0);
    const J3 = try recoilImpulseNs(10.0, 1800.0);
    try std.testing.expectApproxEqAbs(2.0 * J1, J2, 1e-6);
    try std.testing.expectApproxEqAbs(2.0 * J1, J3, 1e-6);
}

test "mean recoil force: J / dt" {
    const F = try meanRecoilForceN(10.0, 900.0, 0.02);
    try std.testing.expectApproxEqAbs(@as(f64, 9000.0 / 0.02), F, 1e-3);
}

test "muzzle energy: 10 kg at 900 m/s = 4.05 MJ" {
    const E = try muzzleEnergyJ(10.0, 900.0);
    try std.testing.expectApproxEqAbs(@as(f64, 4_050_000.0), E, 1e-3);
}

test "muzzle energy scales with V^2" {
    const E1 = try muzzleEnergyJ(10.0, 900.0);
    const E2 = try muzzleEnergyJ(10.0, 1800.0);
    try std.testing.expectApproxEqAbs(4.0, E2 / E1, 1e-9);
}

test "VLS deck pressure: 500 kN over 1 m^2 = 500 kPa" {
    const p = try vlsDeckPressurePa(500_000.0, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 500_000.0), p, 1e-3);
}

test "time to apex: 900 m/s at 30 deg = 900 * 0.5 / 9.81 = 45.87 s" {
    const t = try timeToApexS(900.0, std.math.pi / 6.0, 9.81);
    const expected = 900.0 * 0.5 / 9.81;
    try std.testing.expectApproxEqAbs(expected, t, 1e-9);
}

test "time to apex at 90 deg = V/g" {
    const t = try timeToApexS(900.0, std.math.pi / 2.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 900.0 / 9.81), t, 1e-9);
}

test "vacuum max range at 1000 m/s muzzle = 100 000 / 9.81 m = ~10.2 km" {
    const R = try vacuumMaxRangeM(1000.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0e6 / 9.81), R, 1e-3);
}

test "vacuum range scales with V^2" {
    const R1 = try vacuumMaxRangeM(500.0, 9.81);
    const R2 = try vacuumMaxRangeM(1000.0, 9.81);
    try std.testing.expectApproxEqAbs(4.0, R2 / R1, 1e-9);
}

test "input rejection: zero projectile mass" {
    try std.testing.expectError(Error.NonPositiveMass, recoilImpulseNs(0.0, 900.0));
}

test "input rejection: zero charge time" {
    try std.testing.expectError(Error.NonPositiveDuration, meanRecoilForceN(10.0, 900.0, 0.0));
}

test "input rejection: zero footprint" {
    try std.testing.expectError(Error.NonPositiveArea, vlsDeckPressurePa(500_000.0, 0.0));
}
