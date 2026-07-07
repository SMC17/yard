const std = @import("std");

pub const Error = error{
    NonPositiveMass,
    NegativeVelocity,
    InvalidAddedMassFactor,
};

/// Minorsky's empirical added-mass factor for the struck vessel
/// (lateral motion): mu_struck = 1.4. For the striking vessel
/// (longitudinal): mu_striking = 1.0. Caller may pass any positive
/// value to override for specific hull forms.
pub const mu_minorsky_struck_lateral: f64 = 1.4;
pub const mu_minorsky_striking_longitudinal: f64 = 1.0;

/// Effective mass m_eff = (1 + mu) m_disp for added-mass-corrected
/// kinetic energy. `mu` is the dimensionless added-mass coefficient
/// (added mass / displacement).
pub fn effectiveMassKg(m_disp_kg: f64, mu: f64) Error!f64 {
    if (!(m_disp_kg > 0)) return Error.NonPositiveMass;
    if (!(mu >= 0)) return Error.InvalidAddedMassFactor;
    return (1.0 + mu) * m_disp_kg;
}

/// Kinetic energy E_k = 0.5 m V^2 [J].
pub fn kineticEnergyJ(m_kg: f64, V_mps: f64) Error!f64 {
    if (!(m_kg > 0)) return Error.NonPositiveMass;
    if (!(V_mps >= 0)) return Error.NegativeVelocity;
    return 0.5 * m_kg * V_mps * V_mps;
}

/// Kinetic energy with added mass: E_k = 0.5 (1 + mu) m V^2 [J].
pub fn kineticEnergyWithAddedMassJ(m_disp_kg: f64, mu: f64, V_mps: f64) Error!f64 {
    const m_eff = try effectiveMassKg(m_disp_kg, mu);
    return try kineticEnergyJ(m_eff, V_mps);
}

/// Minorsky right-angle two-ship collision energy absorbed by
/// structure (the dissipated portion of the relative kinetic energy
/// after the two-ship momentum is exchanged). For a striking ship
/// with mass m_a and longitudinal speed V_a, struck ship m_b at rest
/// with lateral added mass factor mu_b, the structurally absorbed
/// energy under perfectly plastic impact is:
///   E_str = 0.5 * m_a * (1 + mu_b) * m_b /
///                ((1 + mu_a) m_a + (1 + mu_b) m_b) * V_a^2.
pub fn rightAngleAbsorbedEnergyJ(
    m_a_kg: f64,
    mu_a: f64,
    V_a_mps: f64,
    m_b_kg: f64,
    mu_b: f64,
) Error!f64 {
    if (!(m_a_kg > 0)) return Error.NonPositiveMass;
    if (!(m_b_kg > 0)) return Error.NonPositiveMass;
    if (!(V_a_mps >= 0)) return Error.NegativeVelocity;
    if (!(mu_a >= 0)) return Error.InvalidAddedMassFactor;
    if (!(mu_b >= 0)) return Error.InvalidAddedMassFactor;
    const num = m_a_kg * (1.0 + mu_b) * m_b_kg;
    const den = (1.0 + mu_a) * m_a_kg + (1.0 + mu_b) * m_b_kg;
    return 0.5 * num / den * V_a_mps * V_a_mps;
}

test "effective mass with mu=0 reduces to displacement" {
    const m = try effectiveMassKg(10_000.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 10_000.0), m, 1e-12);
}

test "effective mass with mu=1.4 is 2.4x displacement" {
    const m = try effectiveMassKg(10_000.0, 1.4);
    try std.testing.expectApproxEqAbs(@as(f64, 24_000.0), m, 1e-12);
}

test "kinetic energy closed form" {
    const E = try kineticEnergyJ(1000.0, 5.0);
    try std.testing.expectApproxEqAbs(@as(f64, 12_500.0), E, 1e-12);
}

test "kinetic energy with added mass scales by (1 + mu)" {
    const E0 = try kineticEnergyWithAddedMassJ(1000.0, 0.0, 5.0);
    const E1 = try kineticEnergyWithAddedMassJ(1000.0, 1.4, 5.0);
    try std.testing.expectApproxEqAbs(2.4 * E0, E1, 1e-12);
}

test "right-angle absorbed energy: equal masses zero-mu special case" {
    // m_a = m_b, mu_a = mu_b = 0 -> E_str = 0.5 * m^2 / (2 m) V^2 = 0.25 m V^2 = 0.5 * E_k_a.
    const E = try rightAngleAbsorbedEnergyJ(1000.0, 0.0, 5.0, 1000.0, 0.0);
    const E_ka = try kineticEnergyJ(1000.0, 5.0);
    try std.testing.expectApproxEqAbs(0.5 * E_ka, E, 1e-12);
}

test "right-angle absorbed energy: striking ship dwarfs struck" {
    // m_a >> m_b -> E_str -> 0.5 (1 + mu_b) m_b V^2.
    const E = try rightAngleAbsorbedEnergyJ(1.0e8, 0.0, 5.0, 1000.0, 1.4);
    const expected = 0.5 * (1.0 + 1.4) * 1000.0 * 25.0;
    try std.testing.expectApproxEqAbs(expected, E, 1.0);
}

test "right-angle absorbed energy: struck ship dwarfs striking" {
    // m_b >> m_a -> E_str -> 0.5 m_a / (1 + mu_a) V^2.
    const E = try rightAngleAbsorbedEnergyJ(1000.0, 0.0, 5.0, 1.0e8, 1.4);
    const expected = 0.5 * 1000.0 * 25.0;
    try std.testing.expectApproxEqAbs(expected, E, 1.0);
}

test "Minorsky default added-mass constants" {
    try std.testing.expectApproxEqAbs(@as(f64, 1.4), mu_minorsky_struck_lateral, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), mu_minorsky_striking_longitudinal, 1e-12);
}

test "input rejection: non-positive mass" {
    try std.testing.expectError(Error.NonPositiveMass, kineticEnergyJ(0.0, 5.0));
    try std.testing.expectError(Error.NonPositiveMass, effectiveMassKg(-1.0, 0.0));
}

test "input rejection: negative velocity" {
    try std.testing.expectError(Error.NegativeVelocity, kineticEnergyJ(1000.0, -1.0));
}

test "input rejection: negative mu" {
    try std.testing.expectError(Error.InvalidAddedMassFactor, effectiveMassKg(1000.0, -0.1));
}
