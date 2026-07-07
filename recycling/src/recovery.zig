const std = @import("std");

pub const Error = error{
    NonPositiveLdt,
    InvalidFraction,
};

/// Material categories recovered from ship recycling.
pub const MaterialCategory = enum {
    steel_plate,
    steel_section,
    non_ferrous,
    cables,
    machinery,
    timber,
    hazardous_waste,

    /// Typical mass fraction of total LDT (Bangladesh / India yard
    /// averages, Marine Engineering Society 2018).
    pub fn fractionOfLDT(self: MaterialCategory) f64 {
        return switch (self) {
            .steel_plate => 0.55,
            .steel_section => 0.25,
            .non_ferrous => 0.04,
            .cables => 0.02,
            .machinery => 0.10,
            .timber => 0.01,
            .hazardous_waste => 0.03,
        };
    }
};

/// Recovered mass [t] for a single category from a ship of LDT.
pub fn recoveredMassT(LDT_ship_t: f64, cat: MaterialCategory) Error!f64 {
    if (!(LDT_ship_t > 0)) return Error.NonPositiveLdt;
    return LDT_ship_t * cat.fractionOfLDT();
}

/// Total mass across all categories. Should sum to LDT (or close to)
/// since fractions sum to 1.0.
pub fn totalRecoveredT(LDT_ship_t: f64) Error!f64 {
    if (!(LDT_ship_t > 0)) return Error.NonPositiveLdt;
    var total: f64 = 0.0;
    inline for (.{
        MaterialCategory.steel_plate,
        MaterialCategory.steel_section,
        MaterialCategory.non_ferrous,
        MaterialCategory.cables,
        MaterialCategory.machinery,
        MaterialCategory.timber,
        MaterialCategory.hazardous_waste,
    }) |c| {
        total += try recoveredMassT(LDT_ship_t, c);
    }
    return total;
}

/// Valorisation [USD] of a recovered category at market price.
pub fn categoryProceedsUSD(
    LDT_ship_t: f64,
    cat: MaterialCategory,
    price_usd_per_t: f64,
) Error!f64 {
    if (!(price_usd_per_t > 0)) return Error.InvalidFraction;
    const m = try recoveredMassT(LDT_ship_t, cat);
    return m * price_usd_per_t;
}

/// Hazardous-waste disposal cost (USD): negative valorisation
/// because the yard pays to dispose of the material.
pub fn hazardousDisposalCostUSD(
    LDT_ship_t: f64,
    disposal_usd_per_t: f64,
) Error!f64 {
    if (!(disposal_usd_per_t > 0)) return Error.InvalidFraction;
    const m = try recoveredMassT(LDT_ship_t, .hazardous_waste);
    return m * disposal_usd_per_t;
}

test "steel plate fraction is 0.55" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.55), MaterialCategory.steel_plate.fractionOfLDT(), 1e-12);
}

test "fractions sum to approximately 1.0" {
    var sum: f64 = 0.0;
    inline for (.{
        MaterialCategory.steel_plate,
        MaterialCategory.steel_section,
        MaterialCategory.non_ferrous,
        MaterialCategory.cables,
        MaterialCategory.machinery,
        MaterialCategory.timber,
        MaterialCategory.hazardous_waste,
    }) |c| sum += c.fractionOfLDT();
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), sum, 1e-12);
}

test "recovered steel-plate mass at 10000 LDT = 5500 t" {
    const m = try recoveredMassT(10_000.0, .steel_plate);
    try std.testing.expectApproxEqAbs(@as(f64, 5500.0), m, 1e-9);
}

test "recovered cables at 10000 LDT = 200 t" {
    const m = try recoveredMassT(10_000.0, .cables);
    try std.testing.expectApproxEqAbs(@as(f64, 200.0), m, 1e-9);
}

test "total recovered equals LDT" {
    const t = try totalRecoveredT(10_000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 10_000.0), t, 1e-9);
}

test "category proceeds: 5500 t steel plate at 350 USD/t = 1.925 M" {
    const p = try categoryProceedsUSD(10_000.0, .steel_plate, 350.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1_925_000.0), p, 1e-3);
}

test "category proceeds scales linearly with price" {
    const p1 = try categoryProceedsUSD(10_000.0, .steel_plate, 350.0);
    const p2 = try categoryProceedsUSD(10_000.0, .steel_plate, 700.0);
    try std.testing.expectApproxEqAbs(2.0 * p1, p2, 1e-3);
}

test "hazardous disposal cost: 300 t at 1500 USD/t = 450 000" {
    const c = try hazardousDisposalCostUSD(10_000.0, 1500.0);
    try std.testing.expectApproxEqAbs(@as(f64, 450_000.0), c, 1e-3);
}

test "input rejection: zero LDT" {
    try std.testing.expectError(Error.NonPositiveLdt, recoveredMassT(0.0, .steel_plate));
}

test "input rejection: zero price" {
    try std.testing.expectError(
        Error.InvalidFraction,
        categoryProceedsUSD(10_000.0, .steel_plate, 0.0),
    );
}

test "input rejection: zero disposal price" {
    try std.testing.expectError(
        Error.InvalidFraction,
        hazardousDisposalCostUSD(10_000.0, 0.0),
    );
}

test "ordering: steel_plate > machinery > non_ferrous fraction" {
    try std.testing.expect(MaterialCategory.steel_plate.fractionOfLDT() >
        MaterialCategory.machinery.fractionOfLDT());
    try std.testing.expect(MaterialCategory.machinery.fractionOfLDT() >
        MaterialCategory.non_ferrous.fractionOfLDT());
}
