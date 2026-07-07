const std = @import("std");

pub const Error = error{
    NonPositiveFuel,
    NonPositiveCapacity,
    NonPositiveDistance,
    InvalidZ,
    InvalidYear,
    UnknownFuel,
    UnequalLength,
};

/// Carbon-conversion factors per MEPC.337(76). Subset of the EEDI
/// catalogue reused here to keep the CII calculator self-contained.
pub const FuelType = enum {
    HFO,
    LFO,
    MDO,
    MGO,
    LNG,
    LPG_propane,
    LPG_butane,
    methanol,
    ethanol,

    pub fn carbonFactor(self: FuelType) f64 {
        return switch (self) {
            .HFO => 3.114,
            .LFO => 3.151,
            .MDO => 3.206,
            .MGO => 3.206,
            .LPG_propane => 3.000,
            .LPG_butane => 3.030,
            .LNG => 2.750,
            .methanol => 1.375,
            .ethanol => 1.913,
        };
    }
};

/// Per-fuel annual consumption entry.
pub const FuelEntry = struct {
    fuel: FuelType,
    consumption_t: f64,
};

/// Attained AER computation:
///   AER = sum_f (FC_f * C_F_f) * 1e6 / (DWT * D)
/// Returns g CO2 per t * nm.
pub fn attainedAERgCO2PerTNm(
    fuels: []const FuelEntry,
    capacity_t: f64,
    distance_nm: f64,
) Error!f64 {
    if (!(capacity_t > 0)) return Error.NonPositiveCapacity;
    if (!(distance_nm > 0)) return Error.NonPositiveDistance;
    var sum: f64 = 0.0;
    for (fuels) |e| {
        if (!(e.consumption_t > 0)) return Error.NonPositiveFuel;
        sum += e.consumption_t * e.fuel.carbonFactor();
    }
    // sum units: t (fuel) * (t CO2 / t fuel) = t CO2.
    // * 1e6 g/t -> g CO2.
    // / (DWT [t] * D [nm]) -> g CO2 / (t * nm).
    return sum * 1.0e6 / (capacity_t * distance_nm);
}

/// MEPC.354(78) Z reduction factor for ship-rating year 2023..2030.
/// Year 2019 baseline = 0 % reduction.
pub fn reductionFactorZ(year: u16) Error!f64 {
    return switch (year) {
        2019 => 0.00,
        2023 => 0.05,
        2024 => 0.07,
        2025 => 0.09,
        2026 => 0.11,
        2027 => 0.13,
        2028 => 0.15,
        2029 => 0.17,
        2030 => 0.19,
        else => Error.InvalidYear,
    };
}

/// Required CII = baseline reference line * (1 - Z). Caller supplies
/// the baseline for the ship type from the corresponding MEPC.353(78)
/// table.
pub fn requiredCIIgCO2PerTNm(baseline_g_per_t_nm: f64, year: u16) Error!f64 {
    if (!(baseline_g_per_t_nm > 0)) return Error.NonPositiveFuel;
    const Z = try reductionFactorZ(year);
    return baseline_g_per_t_nm * (1.0 - Z);
}

/// CII rating bands A..E per MEPC.339(76). The dd vectors are bulk-
/// carrier rating boundaries from MEPC.354(78) Annex 2 Table 1:
///   d1 = 0.86, d2 = 0.94, d3 = 1.06, d4 = 1.18.
pub const Rating = enum { A, B, C, D, E };

pub fn classifyBulkCarrier(attained: f64, required: f64) Rating {
    const ratio = attained / required;
    if (ratio < 0.86) return .A;
    if (ratio < 0.94) return .B;
    if (ratio < 1.06) return .C;
    if (ratio < 1.18) return .D;
    return .E;
}

test "carbon factors propagate from MEPC.337(76)" {
    try std.testing.expectApproxEqAbs(@as(f64, 3.114), FuelType.HFO.carbonFactor(), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.750), FuelType.LNG.carbonFactor(), 1e-12);
}

test "attained AER for a single-fuel HFO voyage" {
    const fe = [_]FuelEntry{
        .{ .fuel = .HFO, .consumption_t = 1000.0 },
    };
    const aer = try attainedAERgCO2PerTNm(&fe, 50_000.0, 60_000.0);
    std.debug.print("\n[VERIFICATION] Attained AER: {d}\n", .{aer});
    // 1000 t * 3.114 = 3114 t CO2 = 3.114e9 g CO2.
    // / (50000 * 60000) = / 3e9 = 1.038.
    const expected = 1000.0 * 3.114 * 1.0e6 / (50_000.0 * 60_000.0);
    try std.testing.expectApproxEqAbs(expected, aer, 1e-9);
    try std.testing.expect(aer > 1.0 and aer < 1.1);
}

test "attained AER scales linearly with fuel consumption" {
    const fe1 = [_]FuelEntry{.{ .fuel = .HFO, .consumption_t = 1000.0 }};
    const fe2 = [_]FuelEntry{.{ .fuel = .HFO, .consumption_t = 2000.0 }};
    const a1 = try attainedAERgCO2PerTNm(&fe1, 50_000.0, 60_000.0);
    const a2 = try attainedAERgCO2PerTNm(&fe2, 50_000.0, 60_000.0);
    try std.testing.expectApproxEqAbs(2.0 * a1, a2, 1e-9);
}

test "attained AER LNG fuel produces lower value than HFO" {
    const fe_hfo = [_]FuelEntry{.{ .fuel = .HFO, .consumption_t = 1000.0 }};
    const fe_lng = [_]FuelEntry{.{ .fuel = .LNG, .consumption_t = 1000.0 }};
    const a_hfo = try attainedAERgCO2PerTNm(&fe_hfo, 50_000.0, 60_000.0);
    const a_lng = try attainedAERgCO2PerTNm(&fe_lng, 50_000.0, 60_000.0);
    try std.testing.expect(a_lng < a_hfo);
    try std.testing.expectApproxEqAbs(2.750 / 3.114, a_lng / a_hfo, 1e-12);
}

test "Z reduction factor 2023 -> 0.05; 2024 -> 0.07; 2030 -> 0.19" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.05), try reductionFactorZ(2023), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.07), try reductionFactorZ(2024), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.19), try reductionFactorZ(2030), 1e-12);
}

test "Z factor monotone increasing 2023..2030" {
    var prev = try reductionFactorZ(2023);
    inline for ([_]u16{ 2024, 2025, 2026, 2027, 2028, 2029, 2030 }) |y| {
        const cur = try reductionFactorZ(y);
        try std.testing.expect(cur > prev);
        prev = cur;
    }
}

test "required CII at baseline 5.0 and 2030: 0.81 * 5.0 = 4.05" {
    const req = try requiredCIIgCO2PerTNm(5.0, 2030);
    try std.testing.expectApproxEqAbs(@as(f64, 0.81 * 5.0), req, 1e-12);
}

test "bulk carrier ratings span A..E correctly" {
    try std.testing.expectEqual(Rating.A, classifyBulkCarrier(0.80, 1.0));
    try std.testing.expectEqual(Rating.B, classifyBulkCarrier(0.90, 1.0));
    try std.testing.expectEqual(Rating.C, classifyBulkCarrier(1.00, 1.0));
    try std.testing.expectEqual(Rating.D, classifyBulkCarrier(1.10, 1.0));
    try std.testing.expectEqual(Rating.E, classifyBulkCarrier(1.20, 1.0));
}

test "input rejection: zero capacity" {
    const fe = [_]FuelEntry{.{ .fuel = .HFO, .consumption_t = 1000.0 }};
    try std.testing.expectError(Error.NonPositiveCapacity, attainedAERgCO2PerTNm(&fe, 0.0, 60_000.0));
}

test "input rejection: zero distance" {
    const fe = [_]FuelEntry{.{ .fuel = .HFO, .consumption_t = 1000.0 }};
    try std.testing.expectError(Error.NonPositiveDistance, attainedAERgCO2PerTNm(&fe, 50_000.0, 0.0));
}

test "input rejection: unknown year" {
    try std.testing.expectError(Error.InvalidYear, reductionFactorZ(2022));
    try std.testing.expectError(Error.InvalidYear, reductionFactorZ(2031));
}
