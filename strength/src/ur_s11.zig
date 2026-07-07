// IACS UR S11: Longitudinal Strength.
//
// Wave-induced vertical bending moments and minimum hull-girder
// section modulus / moment of inertia per IACS Unified Requirement S11.
// Reproduced from
// ~/codex/sources/standards_machine_readable/iacs_ur_s11_longitudinal_strength.yaml.
//
// Symbols:
//   L      rule length (m)
//   B      rule breadth (m)
//   C_B    block coefficient (bounded below at 0.60 per UR S11)
//   f1     navigation factor (1.0 worldwide unrestricted; reduced for
//          service-restricted ships)
//   C      wave coefficient (dimensionless), piecewise across L
//
// Wave bending moment formulas (kN*m):
//   M_wv_hog = +190 * f1 * C * L^2 * B * C_B * 1e-3
//   M_wv_sag = -110 * f1 * C * L^2 * B * (C_B + 0.7) * 1e-3
//
// Wave coefficient C is piecewise in L:
//   90 <= L < 300:  C = 10.75 - ((300 - L) / 100)^1.5
//   300 <= L <= 350: C = 10.75
//   350 < L <= 500: C = 10.75 - ((L - 350) / 150)^1.5
//
// Outside [90, 500] m the formula is not applicable per IACS UR S11.
//
// UR S4 material factor k (per yield stress):
//   mild steel       k = 1.00
//   HT32             k = 0.78
//   HT36             k = 0.72
//   HT40             k = 0.66
//
// Permissible normal stress sigma_perm = 175 / k (N / mm^2).
// Minimum section modulus Z_min = (M_wv + M_sw) / sigma_perm.
// Minimum moment of inertia I_min = 3 * Z_min * L.

const std = @import("std");

pub const Error = error{
    LengthBelowValidity,
    LengthAboveValidity,
    NonPositiveSectionModulus,
};

pub const validity = struct {
    pub const L_min_m: f64 = 90.0;
    pub const L_max_m: f64 = 500.0;
    pub const CB_min: f64 = 0.60;
};

/// Steel grade names with their UR S4 material factor k.
pub const SteelGrade = enum {
    mild,
    ht32,
    ht36,
    ht40,

    pub fn k(self: SteelGrade) f64 {
        return switch (self) {
            .mild => 1.00,
            .ht32 => 0.78,
            .ht36 => 0.72,
            .ht40 => 0.66,
        };
    }

    pub fn yieldMpa(self: SteelGrade) f64 {
        return switch (self) {
            .mild => 235.0,
            .ht32 => 315.0,
            .ht36 => 355.0,
            .ht40 => 390.0,
        };
    }
};

/// UR S11 wave coefficient C(L). Returns Error.LengthBelow/AboveValidity
/// outside [90, 500] m.
pub fn waveCoefficient(L: f64) Error!f64 {
    if (L < validity.L_min_m) return Error.LengthBelowValidity;
    if (L > validity.L_max_m) return Error.LengthAboveValidity;
    if (L < 300.0) {
        const ratio = (300.0 - L) / 100.0;
        return 10.75 - std.math.pow(f64, ratio, 1.5);
    }
    if (L <= 350.0) return 10.75;
    const ratio = (L - 350.0) / 150.0;
    return 10.75 - std.math.pow(f64, ratio, 1.5);
}

/// Wave bending moment in hogging condition (kN*m).
///
/// Block coefficient C_B is bounded below at 0.60 per UR S11.
/// `f1` is the navigation factor (1.0 for worldwide unrestricted).
pub fn waveMomentHog(L: f64, B: f64, C_B: f64, f1: f64) Error!f64 {
    const C = try waveCoefficient(L);
    const cb_eff = if (C_B < validity.CB_min) validity.CB_min else C_B;
    return 190.0 * f1 * C * L * L * B * cb_eff * 1.0e-3;
}

/// Wave bending moment in sagging condition (kN*m). Negative by convention.
pub fn waveMomentSag(L: f64, B: f64, C_B: f64, f1: f64) Error!f64 {
    const C = try waveCoefficient(L);
    const cb_eff = if (C_B < validity.CB_min) validity.CB_min else C_B;
    return -110.0 * f1 * C * L * L * B * (cb_eff + 0.7) * 1.0e-3;
}

/// Permissible normal stress (N / mm^2) for a steel grade.
pub fn permissibleStressMpa(grade: SteelGrade) f64 {
    return 175.0 / grade.k();
}

/// Minimum section modulus Z (m^3) given a design bending moment (kN*m).
/// `M_design` should already combine M_wv and M_sw with the appropriate
/// sign convention; for hogging both are positive; for sagging both
/// negative; the absolute value is used.
pub fn minSectionModulus(M_design_kNm: f64, grade: SteelGrade) Error!f64 {
    const sigma_perm_MPa = permissibleStressMpa(grade);
    // Z [m^3] = |M [kN*m]| / sigma_perm [MPa = N/mm^2 = kN/m^2 * 1e3]
    // Convert: 1 MPa = 1000 kN/m^2; so Z [m^3] = M[kN*m] / (sigma * 1e3).
    const Z = @abs(M_design_kNm) / (sigma_perm_MPa * 1.0e3);
    if (Z <= 0.0) return Error.NonPositiveSectionModulus;
    return Z;
}

/// Minimum moment of inertia I (m^4) of the hull-girder section.
/// Per UR S11: I_min = 3 * Z_min * L.
pub fn minMomentOfInertia(Z_min: f64, L: f64) f64 {
    return 3.0 * Z_min * L;
}

const expectApproxEqRel = std.testing.expectApproxEqRel;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "waveCoefficient at L = 200 matches 10.75 - 1.0" {
    // (300 - 200) / 100 = 1.0; 1.0^1.5 = 1.0; C = 9.75.
    const c = try waveCoefficient(200.0);
    try expectApproxEqAbs(@as(f64, 9.75), c, 1e-12);
}

test "waveCoefficient flat between 300 and 350" {
    try expectApproxEqAbs(@as(f64, 10.75), try waveCoefficient(300.0), 1e-12);
    try expectApproxEqAbs(@as(f64, 10.75), try waveCoefficient(325.0), 1e-12);
    try expectApproxEqAbs(@as(f64, 10.75), try waveCoefficient(350.0), 1e-12);
}

test "waveCoefficient at L = 500 returns 9.75" {
    // (500 - 350) / 150 = 1.0; 1.0^1.5 = 1.0; C = 9.75.
    const c = try waveCoefficient(500.0);
    try expectApproxEqAbs(@as(f64, 9.75), c, 1e-12);
}

test "waveCoefficient continuous at L = 300 and L = 350" {
    const eps: f64 = 1e-3;
    try expectApproxEqAbs(try waveCoefficient(300.0 - eps), try waveCoefficient(300.0 + eps), 1e-4);
    try expectApproxEqAbs(try waveCoefficient(350.0 - eps), try waveCoefficient(350.0 + eps), 1e-4);
}

test "waveCoefficient rejects outside validity" {
    try std.testing.expectError(Error.LengthBelowValidity, waveCoefficient(89.0));
    try std.testing.expectError(Error.LengthAboveValidity, waveCoefficient(501.0));
}

test "waveMomentHog Hughes Paik 2010 bulker example" {
    // Reference: Hughes & Paik (2010), Ship Structural Analysis and Design,
    // Ch. 4 worked example: L = 200 m, B = 32 m, C_B = 0.85.
    // Computed value matches the codex Hughes/Paik cross-check value of
    // approximately 2,016,000 kN*m.
    const M = try waveMomentHog(200.0, 32.0, 0.85, 1.0);
    try expectApproxEqRel(@as(f64, 2.0155e6), M, 1.0e-3);
}

test "waveMomentSag Hughes Paik 2010 bulker example" {
    const M = try waveMomentSag(200.0, 32.0, 0.85, 1.0);
    // Magnitude approximately 2,127,000 kN*m; negative.
    try std.testing.expect(M < 0.0);
    try expectApproxEqRel(@as(f64, -2.1278e6), M, 1.0e-3);
}

test "waveMomentHog positive, waveMomentSag negative" {
    const h = try waveMomentHog(200.0, 32.0, 0.85, 1.0);
    const s = try waveMomentSag(200.0, 32.0, 0.85, 1.0);
    try std.testing.expect(h > 0.0);
    try std.testing.expect(s < 0.0);
}

test "C_B below 0.60 is bounded to 0.60 per UR S11" {
    const M_at_60 = try waveMomentHog(200.0, 32.0, 0.60, 1.0);
    const M_at_50 = try waveMomentHog(200.0, 32.0, 0.50, 1.0);
    try expectApproxEqAbs(M_at_60, M_at_50, 1e-9);
}

test "navigation factor f1 scales linearly" {
    const M_full = try waveMomentHog(200.0, 32.0, 0.85, 1.0);
    const M_half = try waveMomentHog(200.0, 32.0, 0.85, 0.5);
    try expectApproxEqRel(M_full, 2.0 * M_half, 1e-12);
}

test "SteelGrade k values match UR S4 table" {
    try expectApproxEqAbs(@as(f64, 1.00), SteelGrade.mild.k(), 1e-15);
    try expectApproxEqAbs(@as(f64, 0.78), SteelGrade.ht32.k(), 1e-15);
    try expectApproxEqAbs(@as(f64, 0.72), SteelGrade.ht36.k(), 1e-15);
    try expectApproxEqAbs(@as(f64, 0.66), SteelGrade.ht40.k(), 1e-15);
}

test "permissibleStressMpa scales as 175/k" {
    try expectApproxEqAbs(@as(f64, 175.0), permissibleStressMpa(.mild), 1e-12);
    try expectApproxEqRel(@as(f64, 175.0 / 0.78), permissibleStressMpa(.ht32), 1e-12);
}

test "minSectionModulus on Hughes Paik hog moment" {
    const M = try waveMomentHog(200.0, 32.0, 0.85, 1.0);
    const Z = try minSectionModulus(M, .mild);
    // Z = M [kN*m] / (sigma_perm [MPa] * 1000) -> for M = 2.0155e6 kN*m,
    // sigma_perm = 175 MPa, Z = 2.0155e6 / (175 * 1e3) = 11.517 m^3.
    try expectApproxEqRel(@as(f64, 11.517), Z, 1e-3);
}

test "minMomentOfInertia equals 3 Z L" {
    const I = minMomentOfInertia(10.0, 200.0);
    try expectApproxEqAbs(@as(f64, 6000.0), I, 1e-12);
}

test "minSectionModulus rejects zero moment" {
    try std.testing.expectError(Error.NonPositiveSectionModulus, minSectionModulus(0.0, .mild));
}
