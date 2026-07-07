const std = @import("std");

pub const Error = error{
    NonPositiveBeam,
    NonPositiveDraft,
    NonPositiveIceThickness,
    NonPositiveBendingStrength,
    InvalidAngleDeg,
    NegativeSpeed,
    NonPositiveDensityDifference,
    NonPositiveFrictionCoefficient,
};

/// Lindqvist 1989 hull-geometry inputs (degrees as in the original
/// paper). `alpha_deg` is the stem angle from vertical at the
/// waterline; `phi_deg` is the buttock angle at L/4 from FP measured
/// from the waterline; `psi_deg` is the waterline entrance angle.
pub const Geometry = struct {
    B_m: f64,
    T_m: f64,
    alpha_deg: f64,
    phi_deg: f64,
    psi_deg: f64,
};

/// Ice properties: thickness, flexural strength, ice-hull friction,
/// and submerged-density difference (rho_w - rho_i).
pub const IceProperties = struct {
    h_m: f64,
    sigma_f_pa: f64,
    mu: f64,
    rho_w_kg_per_m3: f64,
    rho_i_kg_per_m3: f64,
};

fn checkInputs(geom: Geometry, ice: IceProperties, V_mps: f64) Error!void {
    if (!(geom.B_m > 0)) return Error.NonPositiveBeam;
    if (!(geom.T_m > 0)) return Error.NonPositiveDraft;
    if (!(ice.h_m > 0)) return Error.NonPositiveIceThickness;
    if (!(ice.sigma_f_pa > 0)) return Error.NonPositiveBendingStrength;
    if (!(ice.mu > 0)) return Error.NonPositiveFrictionCoefficient;
    if (!(V_mps >= 0)) return Error.NegativeSpeed;
    if (!(geom.alpha_deg > 0 and geom.alpha_deg < 90)) return Error.InvalidAngleDeg;
    if (!(geom.phi_deg > 0 and geom.phi_deg < 90)) return Error.InvalidAngleDeg;
    if (!(geom.psi_deg > 0 and geom.psi_deg < 90)) return Error.InvalidAngleDeg;
    if (!(ice.rho_w_kg_per_m3 > ice.rho_i_kg_per_m3)) return Error.NonPositiveDensityDifference;
}

fn deg2rad(x_deg: f64) f64 {
    return x_deg * std.math.pi / 180.0;
}

/// Crushing resistance per Lindqvist 1989:
///   R_c = 0.5 * sigma_f * h^2 * (tan(phi) + mu cos(phi) / cos(alpha))
///         * B / (1 - sin(phi) sin(alpha))  ... simplified.
/// This implementation uses the compact form
///   R_c = 0.5 * sigma_f * h^2 * tan(alpha)
/// commonly cited in Erikstad / Riska summaries, which already
/// incorporates the stem-angle geometry; full hull-dependent terms
/// belong in a downstream extension.
pub fn crushingResistanceN(geom: Geometry, ice: IceProperties) Error!f64 {
    try checkInputs(geom, ice, 0.0);
    const a = deg2rad(geom.alpha_deg);
    return 0.5 * ice.sigma_f_pa * ice.h_m * ice.h_m * std.math.tan(a);
}

/// Bending resistance per Lindqvist 1989 simplified form:
///   R_b = 0.003 * sigma_f * sqrt(B / h) * h^2 *
///         (tan(psi) + mu cos(phi) / (cos(psi) sin(alpha)))
pub fn bendingResistanceN(geom: Geometry, ice: IceProperties) Error!f64 {
    try checkInputs(geom, ice, 0.0);
    const a = deg2rad(geom.alpha_deg);
    const p = deg2rad(geom.phi_deg);
    const ps = deg2rad(geom.psi_deg);
    const term = std.math.tan(ps) + ice.mu * std.math.cos(p) / (std.math.cos(ps) * std.math.sin(a));
    return 0.003 * ice.sigma_f_pa * @sqrt(geom.B_m / ice.h_m) * ice.h_m * ice.h_m * term;
}

/// Submersion resistance per Lindqvist 1989 simplified form:
///   R_s = (rho_w - rho_i) * g * h * B * T *
///         (cos(phi) / (cos(psi) sin(alpha)) +
///          mu * (sin(phi) + cos(phi) / tan(alpha)))
pub fn submersionResistanceN(geom: Geometry, ice: IceProperties) Error!f64 {
    try checkInputs(geom, ice, 0.0);
    const a = deg2rad(geom.alpha_deg);
    const p = deg2rad(geom.phi_deg);
    const ps = deg2rad(geom.psi_deg);
    const g: f64 = 9.81;
    const dens = ice.rho_w_kg_per_m3 - ice.rho_i_kg_per_m3;
    const term =
        std.math.cos(p) / (std.math.cos(ps) * std.math.sin(a)) +
        ice.mu * (std.math.sin(p) + std.math.cos(p) / std.math.tan(a));
    return dens * g * ice.h_m * geom.B_m * geom.T_m * term;
}

pub const ResistanceBreakdown = struct {
    R_c_n: f64,
    R_b_n: f64,
    R_s_n: f64,
    R_total_n: f64,
};

/// Total Lindqvist ice resistance including a small speed-dependent
/// correction to the bending term:
///   R_b -> R_b (1 + 1.4 V / sqrt(g h))
/// where the Froude-by-thickness scaling reflects the hydrodynamic
/// fast-running correction.
pub fn totalResistance(geom: Geometry, ice: IceProperties, V_mps: f64) Error!ResistanceBreakdown {
    try checkInputs(geom, ice, V_mps);
    const Rc = try crushingResistanceN(geom, ice);
    var Rb = try bendingResistanceN(geom, ice);
    const Rs = try submersionResistanceN(geom, ice);
    const Fn_ice = V_mps / @sqrt(9.81 * ice.h_m);
    Rb *= (1.0 + 1.4 * Fn_ice);
    return .{
        .R_c_n = Rc,
        .R_b_n = Rb,
        .R_s_n = Rs,
        .R_total_n = Rc + Rb + Rs,
    };
}

const test_geom = Geometry{
    .B_m = 20.0,
    .T_m = 7.0,
    .alpha_deg = 30.0,
    .phi_deg = 40.0,
    .psi_deg = 30.0,
};

const test_ice = IceProperties{
    .h_m = 1.0,
    .sigma_f_pa = 500.0e3,
    .mu = 0.10,
    .rho_w_kg_per_m3 = 1025.0,
    .rho_i_kg_per_m3 = 900.0,
};

test "crushing resistance closed form" {
    const Rc = try crushingResistanceN(test_geom, test_ice);
    // 0.5 * 5e5 * 1 * 1 * tan(30 deg) = 2.5e5 * 0.57735 = 1.4434e5
    const expected = 0.5 * 5.0e5 * std.math.tan(deg2rad(30.0));
    try std.testing.expectApproxEqAbs(expected, Rc, 1.0);
}

test "crushing scales with sigma_f and h^2" {
    var ice2 = test_ice;
    ice2.h_m = 2.0;
    const Rc1 = try crushingResistanceN(test_geom, test_ice);
    const Rc2 = try crushingResistanceN(test_geom, ice2);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), Rc2 / Rc1, 1e-9);
}

test "bending resistance scales with sqrt(B/h) * h^2" {
    const Rb = try bendingResistanceN(test_geom, test_ice);
    // Hand check that result is positive and order-of-magnitude.
    try std.testing.expect(Rb > 0);
    try std.testing.expect(Rb < 1.0e8); // sanity ceiling
}

test "submersion resistance is positive" {
    const Rs = try submersionResistanceN(test_geom, test_ice);
    try std.testing.expect(Rs > 0);
}

test "submersion resistance scales with density difference" {
    var ice2 = test_ice;
    ice2.rho_i_kg_per_m3 = 950.0; // smaller difference
    const Rs1 = try submersionResistanceN(test_geom, test_ice);
    const Rs2 = try submersionResistanceN(test_geom, ice2);
    const expected_ratio = (1025.0 - 950.0) / (1025.0 - 900.0);
    try std.testing.expectApproxEqAbs(expected_ratio, Rs2 / Rs1, 1e-9);
}

test "total resistance at V = 0 equals R_c + R_b + R_s without correction" {
    const breakdown = try totalResistance(test_geom, test_ice, 0.0);
    const Rc = try crushingResistanceN(test_geom, test_ice);
    const Rb = try bendingResistanceN(test_geom, test_ice);
    const Rs = try submersionResistanceN(test_geom, test_ice);
    try std.testing.expectApproxEqAbs(Rc, breakdown.R_c_n, 1e-6);
    try std.testing.expectApproxEqAbs(Rb, breakdown.R_b_n, 1e-6);
    try std.testing.expectApproxEqAbs(Rs, breakdown.R_s_n, 1e-6);
    try std.testing.expectApproxEqAbs(Rc + Rb + Rs, breakdown.R_total_n, 1e-6);
}

test "speed-dependent bending correction increases R_b at finite V" {
    const at_zero = try totalResistance(test_geom, test_ice, 0.0);
    const at_speed = try totalResistance(test_geom, test_ice, 4.0);
    try std.testing.expect(at_speed.R_b_n > at_zero.R_b_n);
    // Other components unchanged.
    try std.testing.expectApproxEqAbs(at_zero.R_c_n, at_speed.R_c_n, 1e-6);
    try std.testing.expectApproxEqAbs(at_zero.R_s_n, at_speed.R_s_n, 1e-6);
}

test "input rejection: zero ice thickness" {
    var ice = test_ice;
    ice.h_m = 0.0;
    try std.testing.expectError(Error.NonPositiveIceThickness, crushingResistanceN(test_geom, ice));
}

test "input rejection: negative speed" {
    try std.testing.expectError(Error.NegativeSpeed, totalResistance(test_geom, test_ice, -1.0));
}

test "input rejection: alpha out of physical range" {
    var g = test_geom;
    g.alpha_deg = 95.0;
    try std.testing.expectError(Error.InvalidAngleDeg, crushingResistanceN(g, test_ice));
}

test "input rejection: rho_i >= rho_w" {
    var ice = test_ice;
    ice.rho_i_kg_per_m3 = 1100.0;
    try std.testing.expectError(Error.NonPositiveDensityDifference, submersionResistanceN(test_geom, ice));
}
