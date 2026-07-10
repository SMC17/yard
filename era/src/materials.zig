//! Shipbuilding structural materials by era, with design allowable stresses.
//!
//! Values are conservative design allowables derived from standard references,
//! not ultimate strengths. Sources per entry:
//!   - Timber: USDA Wood Handbook (FPL-GTR-282) clear-specimen modulus of
//!     rupture at 12% MC, divided by a factor of 8 for duration-of-load,
//!     knots, and marine service (traditional naval timber practice).
//!   - Wrought iron: UTS ~340 MPa longitudinal (Victorian plate practice),
//!     factor 4 on UTS per 19th-century Board of Trade convention.
//!   - Riveted mild steel (1880s): UTS 400-460 MPa, factor 4, before joint
//!     efficiency (apply `riveted_joint_efficiency` to plating allowables).
//!   - Modern steels: class-rule yield (IACS Grade A 235 MPa, AH36 355 MPa)
//!     with a 0.72 utilization factor typical of longitudinal-strength rules.

const std = @import("std");

pub const MaterialId = enum {
    oak,
    teak,
    wrought_iron,
    riveted_steel,
    mild_steel,
    ah36_steel,
};

pub const Material = struct {
    id: MaterialId,
    /// First year the material was in structural shipbuilding use.
    available_from_year: i32,
    density_kg_m3: f64,
    /// Design allowable normal stress [MPa].
    allowable_stress_mpa: f64,
    /// Young's modulus [GPa].
    youngs_modulus_gpa: f64,
    /// Practical maximum hull length for a primary structure of this
    /// material [m] (hogging/longitudinal-strength limit, not a hard law
    /// of physics: the longest wooden hulls ~100 m were already failing).
    max_hull_length_m: f64,
};

pub const riveted_joint_efficiency: f64 = 0.75;

pub const all = [_]Material{
    // White oak: MOR ~105 MPa clear at 12% MC (Wood Handbook), /8.
    .{ .id = .oak, .available_from_year = -3000, .density_kg_m3 = 755, .allowable_stress_mpa = 13.0, .youngs_modulus_gpa = 12.3, .max_hull_length_m = 90.0 },
    // Teak: MOR ~100 MPa clear (Wood Handbook), /8.
    .{ .id = .teak, .available_from_year = 1600, .density_kg_m3 = 655, .allowable_stress_mpa = 12.5, .youngs_modulus_gpa = 10.7, .max_hull_length_m = 90.0 },
    // Wrought iron plate: UTS ~340 MPa, /4.
    .{ .id = .wrought_iron, .available_from_year = 1820, .density_kg_m3 = 7700, .allowable_stress_mpa = 85.0, .youngs_modulus_gpa = 193.0, .max_hull_length_m = 130.0 },
    // Early riveted mild steel: UTS ~430 MPa, /4 (joint efficiency separate).
    // Length limit anchored by RMS Queen Mary (1936, riveted, 311 m).
    .{ .id = .riveted_steel, .available_from_year = 1880, .density_kg_m3 = 7850, .allowable_stress_mpa = 107.0, .youngs_modulus_gpa = 200.0, .max_hull_length_m = 320.0 },
    // Welded IACS Grade A: yield 235 MPa x 0.72.
    .{ .id = .mild_steel, .available_from_year = 1940, .density_kg_m3 = 7850, .allowable_stress_mpa = 169.0, .youngs_modulus_gpa = 206.0, .max_hull_length_m = 400.0 },
    // AH36 higher-tensile: yield 355 MPa x 0.72.
    .{ .id = .ah36_steel, .available_from_year = 1960, .density_kg_m3 = 7850, .allowable_stress_mpa = 256.0, .youngs_modulus_gpa = 206.0, .max_hull_length_m = 460.0 },
};

pub fn get(id: MaterialId) Material {
    for (all) |m| {
        if (m.id == id) return m;
    }
    unreachable;
}

test "allowables are ordered by metallurgical progress" {
    try std.testing.expect(get(.oak).allowable_stress_mpa < get(.wrought_iron).allowable_stress_mpa);
    try std.testing.expect(get(.wrought_iron).allowable_stress_mpa < get(.riveted_steel).allowable_stress_mpa);
    try std.testing.expect(get(.riveted_steel).allowable_stress_mpa < get(.mild_steel).allowable_stress_mpa);
    try std.testing.expect(get(.mild_steel).allowable_stress_mpa < get(.ah36_steel).allowable_stress_mpa);
}

test "timber floats, metal does not" {
    try std.testing.expect(get(.oak).density_kg_m3 < 1000.0);
    try std.testing.expect(get(.teak).density_kg_m3 < 1000.0);
    try std.testing.expect(get(.wrought_iron).density_kg_m3 > 7000.0);
}

test "availability years are monotonic through the metal ages" {
    try std.testing.expect(get(.wrought_iron).available_from_year < get(.riveted_steel).available_from_year);
    try std.testing.expect(get(.riveted_steel).available_from_year < get(.mild_steel).available_from_year);
    try std.testing.expect(get(.mild_steel).available_from_year < get(.ah36_steel).available_from_year);
}
