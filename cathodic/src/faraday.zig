const std = @import("std");

pub const Error = error{
    NonPositiveCurrent,
    NonPositiveTime,
    NonPositiveMolarMass,
    NonPositiveValence,
};

/// Faraday constant in C/mol.
pub const F_C_per_mol: f64 = 96_485.0;

/// Atomic mass of common metals in cathodic-protection contexts
/// (kg / mol).
pub const M_iron_kg_per_mol: f64 = 0.05585;
pub const M_zinc_kg_per_mol: f64 = 0.06538;
pub const M_aluminum_kg_per_mol: f64 = 0.02698;
pub const M_magnesium_kg_per_mol: f64 = 0.02431;

/// Typical valences for the corresponding oxidation reaction.
pub const n_iron: u8 = 2;
pub const n_zinc: u8 = 2;
pub const n_aluminum: u8 = 3;
pub const n_magnesium: u8 = 2;

/// Mass consumed per Faraday's law: m = (I t M) / (n F). All inputs
/// in SI: I in amperes, t in seconds, M in kg/mol; returns kg.
pub fn massConsumedKg(I_a: f64, t_s: f64, M_kg_per_mol: f64, n: u8) Error!f64 {
    if (!(I_a > 0)) return Error.NonPositiveCurrent;
    if (!(t_s > 0)) return Error.NonPositiveTime;
    if (!(M_kg_per_mol > 0)) return Error.NonPositiveMolarMass;
    if (n == 0) return Error.NonPositiveValence;
    const n_f: f64 = @floatFromInt(n);
    return I_a * t_s * M_kg_per_mol / (n_f * F_C_per_mol);
}

/// Annual mass consumption per ampere for a given metal:
/// m_year = (M / (n F)) * 1 A * (365.25 * 86 400 s).
pub fn annualMassPerAmpereKgPerA(M_kg_per_mol: f64, n: u8) Error!f64 {
    if (!(M_kg_per_mol > 0)) return Error.NonPositiveMolarMass;
    if (n == 0) return Error.NonPositiveValence;
    return try massConsumedKg(1.0, 365.25 * 86_400.0, M_kg_per_mol, n);
}

test "Faraday: 1 A for 1 hour consumes M / (n F) * 3600 kg" {
    const m = try massConsumedKg(1.0, 3600.0, M_iron_kg_per_mol, n_iron);
    // 0.05585 / (2 * 96485) * 3600 = 1.04183e-3 kg.
    const expected = 0.05585 / (2.0 * 96_485.0) * 3600.0;
    try std.testing.expectApproxEqAbs(expected, m, 1e-12);
}

test "annual mass for iron at 1 A approximately 9.13 kg/A/yr" {
    const m = try annualMassPerAmpereKgPerA(M_iron_kg_per_mol, n_iron);
    // 0.05585 / (2 * 96485) * (365.25 * 86400) = 9.132 kg.
    try std.testing.expectApproxEqAbs(@as(f64, 9.13), m, 0.02);
}

test "annual mass for aluminum: 3-valent gives lower rate per atom" {
    const m_al = try annualMassPerAmpereKgPerA(M_aluminum_kg_per_mol, n_aluminum);
    // 0.02698 / (3 * 96485) * (365.25 * 86400) = 2.94 kg/A/yr.
    try std.testing.expectApproxEqAbs(@as(f64, 2.94), m_al, 0.02);
}

test "annual mass for zinc approximately 10.7 kg/A/yr" {
    const m = try annualMassPerAmpereKgPerA(M_zinc_kg_per_mol, n_zinc);
    try std.testing.expectApproxEqAbs(@as(f64, 10.69), m, 0.02);
}

test "Faraday: doubling current doubles mass" {
    const m1 = try massConsumedKg(1.0, 3600.0, M_iron_kg_per_mol, n_iron);
    const m2 = try massConsumedKg(2.0, 3600.0, M_iron_kg_per_mol, n_iron);
    try std.testing.expectApproxEqAbs(2.0 * m1, m2, 1e-15);
}

test "Faraday: zero current rejected" {
    try std.testing.expectError(Error.NonPositiveCurrent, massConsumedKg(0.0, 3600.0, M_iron_kg_per_mol, n_iron));
}

test "Faraday: zero valence rejected" {
    try std.testing.expectError(Error.NonPositiveValence, massConsumedKg(1.0, 3600.0, M_iron_kg_per_mol, 0));
}

test "Faraday: zero time rejected" {
    try std.testing.expectError(Error.NonPositiveTime, massConsumedKg(1.0, 0.0, M_iron_kg_per_mol, n_iron));
}
