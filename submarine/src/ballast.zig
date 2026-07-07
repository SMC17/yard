const std = @import("std");

pub const Error = error{
    NonPositiveVolume,
    NonPositiveDensity,
    InvalidTrim,
};

/// Main ballast tank capacity sized to convert surfaced displacement
/// W_surf to submerged displacement W_sub. The reserve buoyancy is
///   V_MBT = (W_sub - W_surf) / (rho g)
/// at the surfaced reference density.
pub fn mbtCapacityM3(
    W_surfaced_n: f64,
    W_submerged_n: f64,
    rho_kg_per_m3: f64,
    g_mps2: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(W_submerged_n > W_surfaced_n)) return Error.NonPositiveVolume;
    return (W_submerged_n - W_surfaced_n) / (rho_kg_per_m3 * g_mps2);
}

/// Reserve-buoyancy fraction:
///   reserve = (W_sub - W_surf) / W_sub.
/// Typical 10-15 % for modern attack submarines, ~30 % for older
/// boats.
pub fn reserveBuoyancyFraction(
    W_surfaced_n: f64,
    W_submerged_n: f64,
) Error!f64 {
    if (!(W_surfaced_n > 0)) return Error.NonPositiveVolume;
    if (!(W_submerged_n > W_surfaced_n)) return Error.NonPositiveVolume;
    return (W_submerged_n - W_surfaced_n) / W_submerged_n;
}

/// Compensating tank trim shift required to compensate for a cargo /
/// payload movement:
///   m_trim * L_trim_arm = m_payload * L_payload_shift
///   m_trim = m_payload * L_payload_shift / L_trim_arm.
pub fn trimTransferMassKg(
    m_payload_kg: f64,
    L_payload_shift_m: f64,
    L_trim_arm_m: f64,
) Error!f64 {
    if (!(m_payload_kg > 0)) return Error.NonPositiveVolume;
    if (!(L_payload_shift_m > 0)) return Error.NonPositiveVolume;
    if (!(L_trim_arm_m > 0)) return Error.InvalidTrim;
    return m_payload_kg * L_payload_shift_m / L_trim_arm_m;
}

/// Required water added to a compensating tank to maintain
/// trim:
///   V_trim = m_trim / rho.
pub fn compensatingWaterVolumeM3(
    m_trim_kg: f64,
    rho_kg_per_m3: f64,
) Error!f64 {
    if (!(m_trim_kg > 0)) return Error.NonPositiveVolume;
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    return m_trim_kg / rho_kg_per_m3;
}

test "MBT capacity: 10 % reserve at 10 MN displacement" {
    // W_surf = 10 MN, W_sub = 11 MN -> reserve = 1 MN / (rho g) ~ 99.4 m^3.
    const V = try mbtCapacityM3(10.0e6, 11.0e6, 1025.0, 9.81);
    const expected = 1.0e6 / (1025.0 * 9.81);
    try std.testing.expectApproxEqAbs(expected, V, 1e-6);
}

test "MBT capacity scales linearly with delta W" {
    const V1 = try mbtCapacityM3(10.0e6, 11.0e6, 1025.0, 9.81);
    const V2 = try mbtCapacityM3(10.0e6, 12.0e6, 1025.0, 9.81);
    try std.testing.expectApproxEqAbs(2.0 * V1, V2, 1e-6);
}

test "reserve buoyancy fraction: W_surf=10, W_sub=12: (2/12)" {
    const f = try reserveBuoyancyFraction(10.0e6, 12.0e6);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0 / 12.0), f, 1e-12);
}

test "reserve buoyancy 0 when W_surf = W_sub" {
    try std.testing.expectError(
        Error.NonPositiveVolume,
        reserveBuoyancyFraction(10.0e6, 10.0e6),
    );
}

test "trim transfer mass: 50 t payload moves 5 m, trim arm 25 m -> 10 t" {
    const m = try trimTransferMassKg(50_000.0, 5.0, 25.0);
    try std.testing.expectApproxEqAbs(@as(f64, 10_000.0), m, 1e-6);
}

test "trim transfer scales linearly with payload mass" {
    const m1 = try trimTransferMassKg(50_000.0, 5.0, 25.0);
    const m2 = try trimTransferMassKg(100_000.0, 5.0, 25.0);
    try std.testing.expectApproxEqAbs(2.0 * m1, m2, 1e-6);
}

test "trim transfer inversely proportional to trim arm" {
    const m1 = try trimTransferMassKg(50_000.0, 5.0, 25.0);
    const m2 = try trimTransferMassKg(50_000.0, 5.0, 50.0);
    try std.testing.expectApproxEqAbs(0.5 * m1, m2, 1e-6);
}

test "compensating water volume: 10 t / 1025 = 9.756 m^3" {
    const V = try compensatingWaterVolumeM3(10_000.0, 1025.0);
    try std.testing.expectApproxEqAbs(@as(f64, 10_000.0 / 1025.0), V, 1e-9);
}

test "input rejection: W_sub < W_surf" {
    try std.testing.expectError(
        Error.NonPositiveVolume,
        mbtCapacityM3(10.0e6, 9.0e6, 1025.0, 9.81),
    );
}

test "input rejection: zero trim arm" {
    try std.testing.expectError(
        Error.InvalidTrim,
        trimTransferMassKg(50_000.0, 5.0, 0.0),
    );
}

test "input rejection: zero rho in compensating volume" {
    try std.testing.expectError(
        Error.NonPositiveDensity,
        compensatingWaterVolumeM3(10_000.0, 0.0),
    );
}
