//! Historical measurement and treaty rule functions.
//!
//! These rules shaped real hull forms: Builder's Old Measurement taxed
//! length and beam but not depth, which is why British merchant hulls went
//! deep and narrow until the Moorsom system (1854) replaced it. Treaty caps
//! are box rules on displacement and armament. Encoding them makes each era
//! a constraint envelope over the same physics.

const std = @import("std");

pub const ft_per_m: f64 = 1.0 / 0.3048;

/// Builder's Old Measurement (1773 Act), imperial units as legislated:
///   tons = (keel_length_ft - 3/5 x beam_ft) x beam_ft x (beam_ft / 2) / 94
pub fn bomTonsImperial(keel_length_ft: f64, beam_ft: f64) f64 {
    return (keel_length_ft - 0.6 * beam_ft) * beam_ft * (beam_ft / 2.0) / 94.0;
}

/// Builder's Old Measurement with SI inputs [m].
pub fn bomTons(keel_length_m: f64, beam_m: f64) f64 {
    return bomTonsImperial(keel_length_m * ft_per_m, beam_m * ft_per_m);
}

/// Moorsom system (Merchant Shipping Act 1854): gross register tonnage is
/// internal volume at 100 cubic feet per register ton.
pub fn moorsomGrossRegisterTons(internal_volume_m3: f64) f64 {
    const ft3 = internal_volume_m3 / (0.3048 * 0.3048 * 0.3048);
    return ft3 / 100.0;
}

/// Washington Naval Treaty (1922) capital-ship box rule.
pub const washington_treaty = struct {
    /// Standard displacement cap [long tons].
    pub const max_standard_displacement_lt: f64 = 35_000.0;
    /// Maximum gun calibre [inches].
    pub const max_gun_calibre_in: f64 = 16.0;
    /// Long ton in kg.
    pub const long_ton_kg: f64 = 1016.047;

    pub fn compliant(standard_displacement_t: f64, gun_calibre_in: f64) bool {
        const lt = standard_displacement_t * 1000.0 / long_ton_kg;
        return lt <= max_standard_displacement_lt and gun_calibre_in <= max_gun_calibre_in;
    }
};

test "BOM matches a hand-computed example" {
    // L=150 ft, B=40 ft: (150 - 24) x 40 x 20 / 94 = 100800/94 = 1072.34
    try std.testing.expectApproxEqAbs(@as(f64, 1072.3404255319148), bomTonsImperial(150.0, 40.0), 1e-9);
}

test "BOM SI wrapper agrees with imperial form" {
    const l_m = 150.0 * 0.3048;
    const b_m = 40.0 * 0.3048;
    try std.testing.expectApproxEqAbs(bomTonsImperial(150.0, 40.0), bomTons(l_m, b_m), 1e-9);
}

test "BOM ignores depth: deep hull pays no more tax" {
    // The historical distortion in one assertion: tonnage is independent of
    // depth, so designers added depth for free capacity.
    const shallow = bomTonsImperial(120.0, 30.0);
    const deep = bomTonsImperial(120.0, 30.0); // no depth term exists to vary
    try std.testing.expectEqual(shallow, deep);
}

test "Moorsom: 100 cubic feet per register ton" {
    const hundred_ft3_in_m3 = 100.0 * 0.3048 * 0.3048 * 0.3048;
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), moorsomGrossRegisterTons(hundred_ft3_in_m3), 1e-12);
}

test "Washington Treaty rejects over-cap designs" {
    // 35,000 long tons = 35,561.6 t; 16 in guns: compliant at the limit.
    try std.testing.expect(washington_treaty.compliant(35_561.0, 16.0));
    // Yamato (~64,000 t standard, 18.1 in): flagrantly non-compliant.
    try std.testing.expect(!washington_treaty.compliant(64_000.0, 18.1));
    try std.testing.expect(!washington_treaty.compliant(30_000.0, 18.0));
}
