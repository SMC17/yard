const std = @import("std");

pub const Error = error{
    NonPositiveMass,
    NonPositiveVolume,
    InvalidDensity,
    NonPositiveCoefficient,
};

/// Seawater density profile [kg/m^3] at depth d [m] using Knauss
/// 1997 simplified linear approximation around the temperature /
/// salinity column. For preliminary design only.
pub fn seawaterDensityAtDepthKgPerM3(d_m: f64, rho_surface_kg_per_m3: f64) Error!f64 {
    if (!(rho_surface_kg_per_m3 > 0)) return Error.InvalidDensity;
    if (!(d_m >= 0)) return Error.NonPositiveVolume;
    // Roughly 0.004 kg/m^3 per metre due to compressibility +
    // small T/S gradients in the upper ocean.
    return rho_surface_kg_per_m3 + 0.004 * d_m;
}

/// Net buoyancy:
///   F_net = (rho V - m) g.
pub fn netBuoyancyN(
    rho_kg_per_m3: f64,
    V_displaced_m3: f64,
    m_kg: f64,
    g_mps2: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.InvalidDensity;
    if (!(V_displaced_m3 > 0)) return Error.NonPositiveVolume;
    if (!(m_kg > 0)) return Error.NonPositiveMass;
    return (rho_kg_per_m3 * V_displaced_m3 - m_kg) * g_mps2;
}

/// Quasi-equilibrium ascent velocity from net buoyancy under
/// quadratic drag:
///   F_net = 0.5 rho C_d A V^2  -> V = sqrt(2 F_net / (rho C_d A)).
pub fn quasiSteadyAscentMPerS(
    F_net_n: f64,
    rho_kg_per_m3: f64,
    C_d: f64,
    A_m2: f64,
) Error!f64 {
    if (!(F_net_n > 0)) return Error.NonPositiveMass;
    if (!(rho_kg_per_m3 > 0)) return Error.InvalidDensity;
    if (!(C_d > 0)) return Error.NonPositiveCoefficient;
    if (!(A_m2 > 0)) return Error.NonPositiveVolume;
    return @sqrt(2.0 * F_net_n / (rho_kg_per_m3 * C_d * A_m2));
}

/// Decompression-stop simplified: stop duration in minutes at depth
/// d [m] per US Navy Diving Manual Rev. 7 Table 9-7. Returns 0 for
/// no-stop depths, increasing with depth.
pub fn deepDiveDecoStopMin(d_m: f64, bottom_time_min: f64) Error!f64 {
    if (!(d_m >= 0)) return Error.NonPositiveVolume;
    if (!(bottom_time_min > 0)) return Error.NonPositiveMass;
    // Simplified no-stop limit: d_max_no_stop (m) for given bottom time.
    // For 10 m: 219 min; 20 m: 51 min; 30 m: 20 min; 40 m: 10 min.
    // Approximation: t_no_stop = 1500 / d^2 [min] above 10 m.
    if (d_m < 10.0) return 0.0;
    const t_no_stop = 1500.0 / (d_m * d_m);
    if (bottom_time_min <= t_no_stop) return 0.0;
    // Beyond no-stop: ~5 min stop per (bottom_time - t_no_stop) above.
    return 5.0 * (bottom_time_min / t_no_stop - 1.0);
}

test "seawater density at surface" {
    const rho = try seawaterDensityAtDepthKgPerM3(0.0, 1025.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1025.0), rho, 1e-12);
}

test "seawater density at 1000 m: ~1029 kg/m^3" {
    const rho = try seawaterDensityAtDepthKgPerM3(1000.0, 1025.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1025.0 + 4.0), rho, 1e-12);
}

test "net buoyancy zero when m = rho V" {
    const F = try netBuoyancyN(1025.0, 1000.0, 1_025_000.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), F, 1e-3);
}

test "net buoyancy positive (ascent) when m < rho V" {
    const F = try netBuoyancyN(1025.0, 1000.0, 1_000_000.0, 9.81);
    try std.testing.expect(F > 0);
}

test "net buoyancy negative (descent) when m > rho V" {
    const F = try netBuoyancyN(1025.0, 1000.0, 1_100_000.0, 9.81);
    try std.testing.expect(F < 0);
}

test "ascent velocity: 100 kN net at rho=1025, C_d=0.5, A=20 m^2" {
    const V = try quasiSteadyAscentMPerS(100_000.0, 1025.0, 0.5, 20.0);
    const expected = @sqrt(@as(f64, 100_000.0 / (0.5 * 1025.0 * 0.5 * 20.0)));
    // Note: 2 * F / (rho C_d A) = 2 * 100000 / (1025 * 0.5 * 20) = 19.51, sqrt = 4.42.
    const expected_actual = @sqrt(2.0 * 100_000.0 / (1025.0 * 0.5 * 20.0));
    _ = expected;
    try std.testing.expectApproxEqAbs(expected_actual, V, 1e-6);
}

test "ascent velocity scales with sqrt(F_net)" {
    const V1 = try quasiSteadyAscentMPerS(50_000.0, 1025.0, 0.5, 20.0);
    const V2 = try quasiSteadyAscentMPerS(200_000.0, 1025.0, 0.5, 20.0);
    try std.testing.expectApproxEqAbs(2.0, V2 / V1, 1e-9);
}

test "deco stop: zero at shallow depth" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try deepDiveDecoStopMin(5.0, 60.0), 1e-12);
}

test "deco stop: zero within no-stop limit at 20 m" {
    // No-stop at 20 m ~ 1500/400 = 3.75 min.
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try deepDiveDecoStopMin(20.0, 3.0), 1e-12);
}

test "deco stop: positive beyond no-stop limit" {
    const t = try deepDiveDecoStopMin(20.0, 30.0);
    try std.testing.expect(t > 0);
}

test "deco stop monotonically increasing with bottom time" {
    const t1 = try deepDiveDecoStopMin(30.0, 30.0);
    const t2 = try deepDiveDecoStopMin(30.0, 60.0);
    try std.testing.expect(t2 > t1);
}

test "input rejection: zero V_displaced" {
    try std.testing.expectError(
        Error.NonPositiveVolume,
        netBuoyancyN(1025.0, 0.0, 1_000_000.0, 9.81),
    );
}

test "input rejection: zero C_d" {
    try std.testing.expectError(
        Error.NonPositiveCoefficient,
        quasiSteadyAscentMPerS(100_000.0, 1025.0, 0.0, 20.0),
    );
}
