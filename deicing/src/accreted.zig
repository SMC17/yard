const std = @import("std");

pub const Error = error{
    NonPositiveArea,
    NonPositiveThickness,
    NonPositiveDensity,
    NonPositiveDuration,
};

/// Ice density [kg/m^3] for hard-rime accretion on superstructure.
pub const rho_ice_seawater_spray_kg_per_m3: f64 = 900.0;

/// Accreted ice weight per surface:
///   W = rho_ice * h_ice * A_surface  [kg].
pub fn accretedMassKg(
    rho_ice_kg_per_m3: f64,
    h_ice_m: f64,
    A_surface_m2: f64,
) Error!f64 {
    if (!(rho_ice_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(h_ice_m > 0)) return Error.NonPositiveThickness;
    if (!(A_surface_m2 > 0)) return Error.NonPositiveArea;
    return rho_ice_kg_per_m3 * h_ice_m * A_surface_m2;
}

/// Indicative ice-accretion rate [m / hr] for Overland icing class
/// per the Coast Guard / NOAA convention applied as a first-order
/// estimator. Caller may pass measured rates instead.
pub fn accretionRateMperHrForClass(cls: anytype) f64 {
    return switch (cls) {
        .none => 0.0,
        .light => 0.003,
        .moderate => 0.010,
        .heavy => 0.020,
        .extreme => 0.040,
    };
}

/// Total weight gain over an exposure duration:
///   W = rho_ice * rate * duration * A_surface.
pub fn totalAccretedWeightKg(
    rho_ice_kg_per_m3: f64,
    rate_m_per_hr: f64,
    duration_hr: f64,
    A_surface_m2: f64,
) Error!f64 {
    if (!(rho_ice_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(rate_m_per_hr >= 0)) return Error.NonPositiveThickness;
    if (!(duration_hr > 0)) return Error.NonPositiveDuration;
    if (!(A_surface_m2 > 0)) return Error.NonPositiveArea;
    const h_ice = rate_m_per_hr * duration_hr;
    return rho_ice_kg_per_m3 * h_ice * A_surface_m2;
}

test "accreted mass at standard density, 10 mm ice, 100 m^2 = 900 kg" {
    const m = try accretedMassKg(rho_ice_seawater_spray_kg_per_m3, 0.010, 100.0);
    try std.testing.expectApproxEqAbs(@as(f64, 900.0), m, 1e-9);
}

test "accreted mass scales linearly with thickness" {
    const m1 = try accretedMassKg(900.0, 0.005, 100.0);
    const m2 = try accretedMassKg(900.0, 0.010, 100.0);
    try std.testing.expectApproxEqAbs(2.0 * m1, m2, 1e-9);
}

test "accreted mass scales linearly with area" {
    const m1 = try accretedMassKg(900.0, 0.010, 50.0);
    const m2 = try accretedMassKg(900.0, 0.010, 100.0);
    try std.testing.expectApproxEqAbs(2.0 * m1, m2, 1e-9);
}

test "icing-class rates monotone increasing" {
    const overland = @import("overland.zig");
    const r_none = accretionRateMperHrForClass(overland.IcingClass.none);
    const r_light = accretionRateMperHrForClass(overland.IcingClass.light);
    const r_mod = accretionRateMperHrForClass(overland.IcingClass.moderate);
    const r_heavy = accretionRateMperHrForClass(overland.IcingClass.heavy);
    const r_ext = accretionRateMperHrForClass(overland.IcingClass.extreme);
    try std.testing.expect(r_none < r_light);
    try std.testing.expect(r_light < r_mod);
    try std.testing.expect(r_mod < r_heavy);
    try std.testing.expect(r_heavy < r_ext);
}

test "total accreted weight: 10 mm/hr * 12 hr * 100 m^2 = 1080 kg at 900 kg/m^3" {
    const W = try totalAccretedWeightKg(900.0, 0.010, 12.0, 100.0);
    // 0.010 * 12 = 0.12 m; 0.12 * 100 m^2 = 12 m^3; * 900 = 10 800 kg.
    try std.testing.expectApproxEqAbs(@as(f64, 10_800.0), W, 1e-9);
}

test "total accreted weight scales linearly in duration" {
    const W1 = try totalAccretedWeightKg(900.0, 0.010, 6.0, 100.0);
    const W2 = try totalAccretedWeightKg(900.0, 0.010, 12.0, 100.0);
    try std.testing.expectApproxEqAbs(2.0 * W1, W2, 1e-9);
}

test "input rejection: zero thickness" {
    try std.testing.expectError(Error.NonPositiveThickness, accretedMassKg(900.0, 0.0, 100.0));
}

test "input rejection: zero duration" {
    try std.testing.expectError(Error.NonPositiveDuration, totalAccretedWeightKg(900.0, 0.010, 0.0, 100.0));
}
