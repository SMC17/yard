const std = @import("std");

pub const Error = error{
    NonPositiveLdt,
    NonPositiveCapacity,
    InvalidYear,
    InvalidRecycler,
};

/// Light Displacement Tonnage = lightship weight in tonnes; the
/// declared HKC "ship recycling capacity" basis.
pub const LdtT = f64;

/// Recycling facility certified annual LDT throughput.
pub const FacilityCapacityLDTPerYear = f64;

/// Match a ship LDT against an annual capacity. The kernel returns
/// the fraction of the facility's annual throughput consumed by a
/// single ship:
///   utilisation = LDT_ship / capacity_annual.
pub fn capacityUtilisation(
    LDT_ship_t: LdtT,
    capacity_annual_t: FacilityCapacityLDTPerYear,
) Error!f64 {
    if (!(LDT_ship_t > 0)) return Error.NonPositiveLdt;
    if (!(capacity_annual_t > 0)) return Error.NonPositiveCapacity;
    return LDT_ship_t / capacity_annual_t;
}

/// HKC enters into force when 15 states representing 40 % of world
/// gross tonnage ratify; the convention adopted in 2009 reached the
/// threshold on 26 June 2023 and enters force 26 June 2025.
pub const hkc_entry_into_force_year: u16 = 2025;

/// Verify a planned recycling year against the HKC entry-into-
/// force date.
pub fn applicabilityForYear(year: u16) Error!bool {
    if (year < 1980 or year > 2100) return Error.InvalidYear;
    return year >= hkc_entry_into_force_year;
}

/// EU SRR 1257/2013 applies to ships flying an EU member state flag
/// (since 31 December 2018) and requires recycling at an EU-listed
/// facility. The kernel exposes the simple flag-state gate.
pub fn euSrrApplicable(eu_flag: bool, facility_on_eu_list: bool) bool {
    if (!eu_flag) return false;
    return facility_on_eu_list;
}

/// Estimated recycling proceeds [USD]:
///   USD = LDT_ship * usd_per_LDT
/// where usd_per_LDT is the current scrap-steel-market price
/// (Bangladesh / India / Pakistan / Turkey vary).
pub fn proceedsUSD(
    LDT_ship_t: LdtT,
    usd_per_ldt: f64,
) Error!f64 {
    if (!(LDT_ship_t > 0)) return Error.NonPositiveLdt;
    if (!(usd_per_ldt > 0)) return Error.NonPositiveCapacity;
    return LDT_ship_t * usd_per_ldt;
}

test "capacity utilisation: 10 000 LDT in 250 000 / year facility = 0.04" {
    const u = try capacityUtilisation(10_000.0, 250_000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.04), u, 1e-12);
}

test "capacity utilisation scales linearly with LDT" {
    const util_a = try capacityUtilisation(10_000.0, 250_000.0);
    const util_b = try capacityUtilisation(20_000.0, 250_000.0);
    try std.testing.expectApproxEqAbs(2.0 * util_a, util_b, 1e-12);
}

test "HKC entry year is 2025" {
    try std.testing.expectEqual(@as(u16, 2025), hkc_entry_into_force_year);
}

test "HKC applicable in 2025 and later" {
    try std.testing.expectEqual(true, try applicabilityForYear(2025));
    try std.testing.expectEqual(true, try applicabilityForYear(2030));
}

test "HKC not applicable in 2024" {
    try std.testing.expectEqual(false, try applicabilityForYear(2024));
}

test "HKC year out of range rejected" {
    try std.testing.expectError(Error.InvalidYear, applicabilityForYear(1970));
    try std.testing.expectError(Error.InvalidYear, applicabilityForYear(2200));
}

test "EU SRR requires EU flag AND EU-listed facility" {
    try std.testing.expectEqual(true, euSrrApplicable(true, true));
    try std.testing.expectEqual(false, euSrrApplicable(true, false));
    try std.testing.expectEqual(false, euSrrApplicable(false, true));
    try std.testing.expectEqual(false, euSrrApplicable(false, false));
}

test "proceeds at 500 USD/LDT for 8 000 LDT ship = 4 000 000 USD" {
    const usd = try proceedsUSD(8_000.0, 500.0);
    try std.testing.expectApproxEqAbs(@as(f64, 4_000_000.0), usd, 1e-3);
}

test "proceeds scales linearly with LDT and price" {
    const usd_a = try proceedsUSD(8_000.0, 500.0);
    const usd_b = try proceedsUSD(16_000.0, 500.0);
    const usd_c = try proceedsUSD(8_000.0, 1000.0);
    try std.testing.expectApproxEqAbs(2.0 * usd_a, usd_b, 1e-3);
    try std.testing.expectApproxEqAbs(2.0 * usd_a, usd_c, 1e-3);
}

test "input rejection: zero LDT" {
    try std.testing.expectError(Error.NonPositiveLdt, capacityUtilisation(0.0, 250_000.0));
}

test "input rejection: zero capacity" {
    try std.testing.expectError(Error.NonPositiveCapacity, capacityUtilisation(10_000.0, 0.0));
}

test "input rejection: zero USD/LDT" {
    try std.testing.expectError(Error.NonPositiveCapacity, proceedsUSD(8_000.0, 0.0));
}
