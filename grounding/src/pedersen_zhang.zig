const std = @import("std");

pub const Error = error{
    NonPositiveMass,
    NegativeVelocity,
    NonPositivePlateThickness,
    NonPositiveYieldStrength,
    InvalidRockHeight,
    InvalidAddedMassFactor,
    NonPositiveDistance,
};

/// Kinetic energy of the grounding ship including added-mass
/// correction for surge:
///   E_kin = 0.5 (1 + mu_x) m V^2 [J].
/// Typical mu_x = 0.05 for the longitudinal added mass.
pub fn kineticEnergyJ(m_kg: f64, mu_x: f64, V_mps: f64) Error!f64 {
    if (!(m_kg > 0)) return Error.NonPositiveMass;
    if (!(V_mps >= 0)) return Error.NegativeVelocity;
    if (!(mu_x >= 0)) return Error.InvalidAddedMassFactor;
    return 0.5 * (1.0 + mu_x) * m_kg * V_mps * V_mps;
}

/// Pedersen-Zhang 2000 simplified mean horizontal force during raking:
///   F_H = sigma_y * t * h_r * C_g
/// where sigma_y is the plate yield strength, t the plate thickness,
/// h_r the rock height above the seabed, and C_g a non-dimensional
/// shape factor for the wedge-and-tearing mode (Pedersen-Zhang use
/// 1.62 for the smooth-rock asperity case).
pub fn meanHorizontalForceN(
    sigma_y_pa: f64,
    plate_thickness_m: f64,
    rock_height_m: f64,
    C_g: f64,
) Error!f64 {
    if (!(sigma_y_pa > 0)) return Error.NonPositiveYieldStrength;
    if (!(plate_thickness_m > 0)) return Error.NonPositivePlateThickness;
    if (!(rock_height_m > 0)) return Error.InvalidRockHeight;
    if (!(C_g > 0)) return Error.NonPositiveYieldStrength;
    return sigma_y_pa * plate_thickness_m * rock_height_m * C_g;
}

/// Pedersen-Zhang shape factor for smooth-rock raking. Default value
/// is 1.62. Caller may pass another factor for the sharp-asperity
/// (~ 2.0) or blunt-asperity (~ 1.3) regimes.
pub const C_g_smooth_rock: f64 = 1.62;

/// Damage length L_damage = E_kin / F_H (energy / force, balance).
pub fn dampageLengthM(E_kin_j: f64, F_H_n: f64) Error!f64 {
    if (!(E_kin_j >= 0)) return Error.NonPositiveDistance;
    if (!(F_H_n > 0)) return Error.NonPositiveDistance;
    return E_kin_j / F_H_n;
}

pub const GroundingInputs = struct {
    /// Ship displacement mass [kg].
    m_kg: f64,
    /// Longitudinal added-mass factor (default 0.05).
    mu_x: f64,
    /// Approach speed at first contact [m/s].
    V_mps: f64,
    /// Bottom plate yield stress [Pa].
    sigma_y_pa: f64,
    /// Bottom plate thickness [m].
    plate_thickness_m: f64,
    /// Mean rock height above the seabed [m].
    rock_height_m: f64,
    /// Shape factor C_g.
    C_g: f64,
};

pub const GroundingResult = struct {
    E_kin_j: f64,
    F_H_n: f64,
    damage_length_m: f64,
};

pub fn analyseGrounding(in: GroundingInputs) Error!GroundingResult {
    const Ek = try kineticEnergyJ(in.m_kg, in.mu_x, in.V_mps);
    const FH = try meanHorizontalForceN(
        in.sigma_y_pa,
        in.plate_thickness_m,
        in.rock_height_m,
        in.C_g,
    );
    const L = try dampageLengthM(Ek, FH);
    return .{ .E_kin_j = Ek, .F_H_n = FH, .damage_length_m = L };
}

test "kinetic energy at mu=0.05, m=10000 t, V=6 m/s" {
    const m = 10_000_000.0; // 10000 t
    const E = try kineticEnergyJ(m, 0.05, 6.0);
    const expected = 0.5 * 1.05 * 10_000_000.0 * 36.0;
    try std.testing.expectApproxEqAbs(expected, E, 1.0);
}

test "horizontal force for steel plate at sigma_y=235 MPa, t=20 mm, h_r=2 m, C_g=1.62" {
    const F = try meanHorizontalForceN(235e6, 0.020, 2.0, C_g_smooth_rock);
    const expected = 235e6 * 0.020 * 2.0 * 1.62;
    try std.testing.expectApproxEqAbs(expected, F, 1.0);
    // Order of magnitude: 1.52e7 N.
    try std.testing.expect(F > 1.5e7 and F < 1.6e7);
}

test "damage length: E=10 MJ, F=10 MN -> 1 m" {
    const L = try dampageLengthM(10.0e6, 10.0e6);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), L, 1e-12);
}

test "analyseGrounding composes the three steps" {
    const in: GroundingInputs = .{
        .m_kg = 10_000_000.0,
        .mu_x = 0.05,
        .V_mps = 6.0,
        .sigma_y_pa = 235e6,
        .plate_thickness_m = 0.020,
        .rock_height_m = 2.0,
        .C_g = C_g_smooth_rock,
    };
    const r = try analyseGrounding(in);
    const Ek_expected = 0.5 * 1.05 * 10_000_000.0 * 36.0;
    const FH_expected = 235e6 * 0.020 * 2.0 * 1.62;
    try std.testing.expectApproxEqAbs(Ek_expected, r.E_kin_j, 1.0);
    try std.testing.expectApproxEqAbs(FH_expected, r.F_H_n, 1.0);
    try std.testing.expectApproxEqAbs(Ek_expected / FH_expected, r.damage_length_m, 1e-6);
}

test "kinetic energy mu=0 reduces to 0.5 m V^2" {
    const E = try kineticEnergyJ(1000.0, 0.0, 5.0);
    try std.testing.expectApproxEqAbs(@as(f64, 12_500.0), E, 1e-12);
}

test "horizontal force scales linearly in plate thickness" {
    const F1 = try meanHorizontalForceN(235e6, 0.020, 2.0, 1.62);
    const F2 = try meanHorizontalForceN(235e6, 0.040, 2.0, 1.62);
    try std.testing.expectApproxEqAbs(2.0 * F1, F2, 1e-6);
}

test "horizontal force scales linearly in rock height" {
    const F1 = try meanHorizontalForceN(235e6, 0.020, 1.0, 1.62);
    const F2 = try meanHorizontalForceN(235e6, 0.020, 3.0, 1.62);
    try std.testing.expectApproxEqAbs(3.0 * F1, F2, 1e-6);
}

test "damage length: doubling speed quadruples damage" {
    const in1: GroundingInputs = .{
        .m_kg = 10_000_000.0, .mu_x = 0.05, .V_mps = 4.0,
        .sigma_y_pa = 235e6, .plate_thickness_m = 0.020,
        .rock_height_m = 2.0, .C_g = 1.62,
    };
    const in2: GroundingInputs = .{
        .m_kg = 10_000_000.0, .mu_x = 0.05, .V_mps = 8.0,
        .sigma_y_pa = 235e6, .plate_thickness_m = 0.020,
        .rock_height_m = 2.0, .C_g = 1.62,
    };
    const r1 = try analyseGrounding(in1);
    const r2 = try analyseGrounding(in2);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), r2.damage_length_m / r1.damage_length_m, 1e-9);
}

test "input rejection: negative velocity" {
    try std.testing.expectError(Error.NegativeVelocity, kineticEnergyJ(1000.0, 0.05, -1.0));
}

test "input rejection: zero plate thickness" {
    try std.testing.expectError(Error.NonPositivePlateThickness, meanHorizontalForceN(235e6, 0.0, 2.0, 1.62));
}

test "input rejection: zero rock height" {
    try std.testing.expectError(Error.InvalidRockHeight, meanHorizontalForceN(235e6, 0.020, 0.0, 1.62));
}
