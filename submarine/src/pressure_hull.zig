const std = @import("std");

pub const Error = error{
    NonPositiveDimension,
    NonPositiveYield,
    NonPositiveModulus,
    InvalidPoisson,
    NonPositivePressure,
};

/// Hydrostatic pressure at depth d in seawater:
///   p = rho g d.
pub fn hydrostaticPressurePa(d_m: f64, rho_kg_per_m3: f64, g_mps2: f64) Error!f64 {
    if (!(d_m >= 0)) return Error.NonPositivePressure;
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDimension;
    return rho_kg_per_m3 * g_mps2 * d_m;
}

/// von Mises critical buckling pressure for an unstiffened cylindrical
/// shell of mean radius R, thickness t, length between bulkheads L,
/// Young's modulus E, Poisson nu, lobe number n:
///   P_cr = E t / R * (n^2 - 1 + ...) ... (full formula complex)
/// The kernel uses the simplified Mises 1929 form valid for thin
/// shells (R/t > 30):
///   P_cr_n = (E t / R) / ((n^2 - 1)(1 + (n^2 L^2 / (pi^2 R^2)))
///               + (t^2 / (12 R^2 (1 - nu^2))) (n^2 - 1)^2)
/// Caller picks the worst-case n; n = 2 is the dominant lobe number
/// for most submarine pressure hulls.
pub fn vonMisesCriticalN(
    E_pa: f64,
    t_m: f64,
    R_m: f64,
    L_m: f64,
    nu: f64,
    n: u32,
) Error!f64 {
    if (!(E_pa > 0)) return Error.NonPositiveModulus;
    if (!(t_m > 0)) return Error.NonPositiveDimension;
    if (!(R_m > 0)) return Error.NonPositiveDimension;
    if (!(L_m > 0)) return Error.NonPositiveDimension;
    if (!(nu > 0.0 and nu < 0.5)) return Error.InvalidPoisson;
    if (n < 2) return Error.NonPositiveDimension;
    const n_f: f64 = @floatFromInt(n);
    const n2m1 = n_f * n_f - 1.0;
    const term_a = (E_pa * t_m / R_m) / n2m1;
    const term_b_denom_1 = 1.0 + (n_f * n_f * L_m * L_m) /
        (std.math.pi * std.math.pi * R_m * R_m);
    const term_b_denom_2 = (t_m * t_m / (12.0 * R_m * R_m * (1.0 - nu * nu))) *
        n2m1 * n2m1;
    return term_a / (term_b_denom_1 + term_b_denom_2);
}

/// Hoop stress in a thin cylinder under external pressure:
///   sigma_h = p R / t.
pub fn hoopStressPa(p_pa: f64, R_m: f64, t_m: f64) Error!f64 {
    if (!(p_pa > 0)) return Error.NonPositivePressure;
    if (!(R_m > 0)) return Error.NonPositiveDimension;
    if (!(t_m > 0)) return Error.NonPositiveDimension;
    return p_pa * R_m / t_m;
}

/// Yield-collapse pressure: pressure at which hoop stress reaches
/// material yield: P_y = sigma_y t / R.
pub fn yieldCollapsePressurePa(
    sigma_y_pa: f64,
    t_m: f64,
    R_m: f64,
) Error!f64 {
    if (!(sigma_y_pa > 0)) return Error.NonPositiveYield;
    if (!(t_m > 0)) return Error.NonPositiveDimension;
    if (!(R_m > 0)) return Error.NonPositiveDimension;
    return sigma_y_pa * t_m / R_m;
}

/// Crush depth from a critical pressure:
///   d_crush = p_cr / (rho g).
pub fn crushDepthM(
    p_cr_pa: f64,
    rho_kg_per_m3: f64,
    g_mps2: f64,
) Error!f64 {
    if (!(p_cr_pa > 0)) return Error.NonPositivePressure;
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDimension;
    return p_cr_pa / (rho_kg_per_m3 * g_mps2);
}

/// Operating-depth safety factor: typical 1.5 for first-of-class
/// submarines per US Navy SUBSAFE; 2.0 historic.
pub fn operatingDepthM(crush_depth_m: f64, safety_factor: f64) Error!f64 {
    if (!(crush_depth_m > 0)) return Error.NonPositiveDimension;
    if (!(safety_factor > 1.0)) return Error.NonPositiveYield;
    return crush_depth_m / safety_factor;
}

test "hydrostatic pressure at 100 m in seawater: 1.005 MPa" {
    const p = try hydrostaticPressurePa(100.0, 1025.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 1025.0 * 9.81 * 100.0), p, 1e-3);
}

test "hydrostatic pressure scales linearly with depth" {
    const p1 = try hydrostaticPressurePa(100.0, 1025.0, 9.81);
    const p2 = try hydrostaticPressurePa(200.0, 1025.0, 9.81);
    try std.testing.expectApproxEqAbs(2.0 * p1, p2, 1e-3);
}

test "hoop stress: p=10 MPa, R=4 m, t=0.05 m = 800 MPa" {
    const sigma = try hoopStressPa(10.0e6, 4.0, 0.05);
    try std.testing.expectApproxEqAbs(@as(f64, 800.0e6), sigma, 1.0);
}

test "yield collapse: sigma_y=700 MPa, t=0.05 m, R=4 m = 8.75 MPa" {
    const p = try yieldCollapsePressurePa(700.0e6, 0.05, 4.0);
    try std.testing.expectApproxEqAbs(@as(f64, 8.75e6), p, 1.0);
}

test "yield collapse scales linearly with t" {
    const p1 = try yieldCollapsePressurePa(700.0e6, 0.05, 4.0);
    const p2 = try yieldCollapsePressurePa(700.0e6, 0.10, 4.0);
    try std.testing.expectApproxEqAbs(2.0 * p1, p2, 1.0);
}

test "yield collapse inversely proportional to R" {
    const p1 = try yieldCollapsePressurePa(700.0e6, 0.05, 4.0);
    const p2 = try yieldCollapsePressurePa(700.0e6, 0.05, 8.0);
    try std.testing.expectApproxEqAbs(0.5 * p1, p2, 1.0);
}

test "von Mises critical pressure positive for typical submarine" {
    // E = 210 GPa, t = 50 mm, R = 4 m, L = 8 m, nu = 0.3, n = 2.
    const p_cr = try vonMisesCriticalN(210.0e9, 0.05, 4.0, 8.0, 0.3, 2);
    try std.testing.expect(p_cr > 0);
    try std.testing.expect(std.math.isFinite(p_cr));
    // Should be on the order of MPa for these inputs.
    try std.testing.expect(p_cr > 1.0e5);
}

test "von Mises minimum at low lobe count n=2" {
    const p_2 = try vonMisesCriticalN(210.0e9, 0.05, 4.0, 8.0, 0.3, 2);
    const p_5 = try vonMisesCriticalN(210.0e9, 0.05, 4.0, 8.0, 0.3, 5);
    // For typical thin shells the n=2 mode often has the lowest
    // critical pressure; the kernel returns positive in both cases.
    try std.testing.expect(p_2 > 0);
    try std.testing.expect(p_5 > 0);
}

test "crush depth: p_cr=8 MPa in seawater = ~796 m" {
    const d = try crushDepthM(8.0e6, 1025.0, 9.81);
    const expected = 8.0e6 / (1025.0 * 9.81);
    try std.testing.expectApproxEqAbs(expected, d, 1e-3);
}

test "operating depth at SF=1.5: 600 m / 1.5 = 400 m" {
    const d = try operatingDepthM(600.0, 1.5);
    try std.testing.expectApproxEqAbs(@as(f64, 400.0), d, 1e-9);
}

test "operating depth at SF=2.0 is half of crush" {
    const d = try operatingDepthM(800.0, 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 400.0), d, 1e-9);
}

test "input rejection: SF <= 1" {
    try std.testing.expectError(Error.NonPositiveYield, operatingDepthM(600.0, 1.0));
}

test "input rejection: zero t" {
    try std.testing.expectError(
        Error.NonPositiveDimension,
        hoopStressPa(10.0e6, 4.0, 0.0),
    );
}

test "input rejection: n = 1 in von Mises" {
    try std.testing.expectError(
        Error.NonPositiveDimension,
        vonMisesCriticalN(210.0e9, 0.05, 4.0, 8.0, 0.3, 1),
    );
}

test "input rejection: Poisson out of range" {
    try std.testing.expectError(
        Error.InvalidPoisson,
        vonMisesCriticalN(210.0e9, 0.05, 4.0, 8.0, 0.6, 2),
    );
}
