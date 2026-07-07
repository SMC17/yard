const std = @import("std");

pub const Error = error{
    NonPositiveMass,
    NonPositiveVolume,
    InvalidStowage,
};

/// Cargo class with typical stowage factor [m^3 / tonne] used to
/// convert deadweight tonnes to hold-volume requirement.
pub const CargoClass = enum {
    /// Wheat / barley / corn (bulk grain).
    grain,
    /// Iron ore.
    iron_ore,
    /// Coal (bulk).
    coal,
    /// Cement (bulk).
    cement,
    /// Steel coils / plate.
    steel_products,
    /// Bagged sugar.
    bagged_sugar,
    /// Pallet stowed mixed general cargo.
    general_cargo_palletised,
    /// Crude oil / fuel oil.
    crude_oil,
    /// Liquid natural gas (cryogenic, m^3/t includes hold).
    LNG,

    /// Representative stowage factor [m^3/t] per Thomas's Stowage
    /// + Carriage of Goods by Sea (Stevens) commentary.
    pub fn stowageFactor(self: CargoClass) f64 {
        return switch (self) {
            .grain => 1.45,
            .iron_ore => 0.40,
            .coal => 1.20,
            .cement => 0.65,
            .steel_products => 0.40,
            .bagged_sugar => 1.30,
            .general_cargo_palletised => 1.80,
            .crude_oil => 1.10,
            .LNG => 2.20,
        };
    }
};

/// Required hold volume [m^3] for a given deadweight tonnage:
///   V = m_t * SF * (1 + broken_stowage_fraction).
pub fn requiredHoldVolumeM3(
    m_tonnes: f64,
    cls: CargoClass,
    broken_stowage_fraction: f64,
) Error!f64 {
    if (!(m_tonnes > 0)) return Error.NonPositiveMass;
    if (!(broken_stowage_fraction >= 0 and broken_stowage_fraction < 1.0)) {
        return Error.InvalidStowage;
    }
    return m_tonnes * cls.stowageFactor() * (1.0 + broken_stowage_fraction);
}

/// Maximum loadable mass [t] given a hold volume:
///   m = V / (SF * (1 + broken_stowage_fraction)).
pub fn maxLoadableMassT(
    V_hold_m3: f64,
    cls: CargoClass,
    broken_stowage_fraction: f64,
) Error!f64 {
    if (!(V_hold_m3 > 0)) return Error.NonPositiveVolume;
    if (!(broken_stowage_fraction >= 0 and broken_stowage_fraction < 1.0)) {
        return Error.InvalidStowage;
    }
    return V_hold_m3 / (cls.stowageFactor() * (1.0 + broken_stowage_fraction));
}

/// Load density [t/m^3] of cargo in the hold:
///   rho_cargo = 1 / SF.
pub fn loadDensityTPerM3(cls: CargoClass) f64 {
    return 1.0 / cls.stowageFactor();
}

/// Broken-stowage allowance for breakbulk:
///   typical 5-10 % for general cargo, 0 % for bulk powder, 15-20 %
///   for awkwardly-shaped breakbulk.
pub const broken_stowage_general_cargo: f64 = 0.10;
pub const broken_stowage_bulk_powder: f64 = 0.0;
pub const broken_stowage_awkward_breakbulk: f64 = 0.20;

test "iron ore stowage factor 0.40" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.40), CargoClass.iron_ore.stowageFactor(), 1e-12);
}

test "LNG stowage factor 2.20" {
    try std.testing.expectApproxEqAbs(@as(f64, 2.20), CargoClass.LNG.stowageFactor(), 1e-12);
}

test "iron ore < coal < grain stowage factor" {
    try std.testing.expect(CargoClass.iron_ore.stowageFactor() < CargoClass.coal.stowageFactor());
    try std.testing.expect(CargoClass.coal.stowageFactor() < CargoClass.grain.stowageFactor());
}

test "required hold volume: 10000 t grain at 10% broken stowage" {
    const V = try requiredHoldVolumeM3(10_000.0, .grain, 0.10);
    // 10000 * 1.45 * 1.10 = 15 950 m^3.
    try std.testing.expectApproxEqAbs(@as(f64, 15_950.0), V, 1e-6);
}

test "max loadable mass inverts the volume formula" {
    const V = try requiredHoldVolumeM3(10_000.0, .grain, 0.10);
    const m = try maxLoadableMassT(V, .grain, 0.10);
    try std.testing.expectApproxEqAbs(@as(f64, 10_000.0), m, 1e-6);
}

test "load density: iron ore = 1 / 0.40 = 2.5 t/m^3" {
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), loadDensityTPerM3(.iron_ore), 1e-12);
}

test "load density: LNG = 1 / 2.20 = 0.4545" {
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 2.20), loadDensityTPerM3(.LNG), 1e-12);
}

test "broken-stowage zero gives bare stowage factor volume" {
    const V = try requiredHoldVolumeM3(1000.0, .iron_ore, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 400.0), V, 1e-9);
}

test "broken-stowage 20% increases V by 20%" {
    const V0 = try requiredHoldVolumeM3(1000.0, .general_cargo_palletised, 0.0);
    const V1 = try requiredHoldVolumeM3(1000.0, .general_cargo_palletised, 0.20);
    try std.testing.expectApproxEqAbs(1.2 * V0, V1, 1e-6);
}

test "input rejection: zero mass" {
    try std.testing.expectError(Error.NonPositiveMass, requiredHoldVolumeM3(0.0, .grain, 0.1));
}

test "input rejection: broken stowage >= 1" {
    try std.testing.expectError(Error.InvalidStowage, requiredHoldVolumeM3(1000.0, .grain, 1.0));
}
