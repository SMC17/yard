const std = @import("std");

pub const Error = error{
    NonPositivePower,
    NonPositiveArea,
    NonPositiveGain,
    NonPositiveWavelength,
    NonPositiveRadius,
    NonPositiveSensitivity,
};

/// Radar cross-section [m^2] of a flat plate of area A at normal
/// incidence: sigma = 4 pi A^2 / lambda^2.
pub fn flatPlateNormalIncidenceM2(
    A_m2: f64,
    lambda_m: f64,
) Error!f64 {
    if (!(A_m2 > 0)) return Error.NonPositiveArea;
    if (!(lambda_m > 0)) return Error.NonPositiveWavelength;
    return 4.0 * std.math.pi * A_m2 * A_m2 / (lambda_m * lambda_m);
}

/// Geometric optics RCS [m^2] of a perfectly conducting sphere of
/// radius r in the high-frequency limit kr >> 1:
///   sigma = pi r^2.
pub fn sphereGeometricM2(r_m: f64) Error!f64 {
    if (!(r_m > 0)) return Error.NonPositiveRadius;
    return std.math.pi * r_m * r_m;
}

/// Corner reflector (trihedral) RCS [m^2] at the boresight:
///   sigma = 12 pi a^4 / lambda^2
/// where a is the side length of each triangular face.
pub fn trihedralCornerReflectorM2(a_m: f64, lambda_m: f64) Error!f64 {
    if (!(a_m > 0)) return Error.NonPositiveArea;
    if (!(lambda_m > 0)) return Error.NonPositiveWavelength;
    return 12.0 * std.math.pi * std.math.pow(f64, a_m, 4) /
        (lambda_m * lambda_m);
}

/// Free-space radar range equation:
///   R_max = ((P_t G^2 lambda^2 sigma) / ((4 pi)^3 P_min))^(1/4).
pub fn radarRangeM(
    P_t_w: f64,
    G_linear: f64,
    lambda_m: f64,
    sigma_m2: f64,
    P_min_w: f64,
) Error!f64 {
    if (!(P_t_w > 0)) return Error.NonPositivePower;
    if (!(G_linear > 0)) return Error.NonPositiveGain;
    if (!(lambda_m > 0)) return Error.NonPositiveWavelength;
    if (!(sigma_m2 > 0)) return Error.NonPositiveArea;
    if (!(P_min_w > 0)) return Error.NonPositiveSensitivity;
    const four_pi_cubed = 64.0 * std.math.pow(f64, std.math.pi, 3);
    const numerator = P_t_w * G_linear * G_linear *
        lambda_m * lambda_m * sigma_m2;
    return std.math.pow(f64, numerator / (four_pi_cubed * P_min_w), 0.25);
}

/// Antenna gain from physical aperture:
///   G = 4 pi A_eff / lambda^2.
pub fn gainFromAperture(A_eff_m2: f64, lambda_m: f64) Error!f64 {
    if (!(A_eff_m2 > 0)) return Error.NonPositiveArea;
    if (!(lambda_m > 0)) return Error.NonPositiveWavelength;
    return 4.0 * std.math.pi * A_eff_m2 / (lambda_m * lambda_m);
}

/// Convert RCS in dBsm to m^2 and vice versa.
pub fn dBsmToM2(dbsm: f64) f64 {
    return std.math.pow(f64, 10.0, dbsm / 10.0);
}

pub fn m2ToDBsm(sigma_m2: f64) Error!f64 {
    if (!(sigma_m2 > 0)) return Error.NonPositiveArea;
    return 10.0 * std.math.log10(sigma_m2);
}

test "flat plate at A = 1 m^2, lambda = 0.03 m (X-band)" {
    const sigma = try flatPlateNormalIncidenceM2(1.0, 0.03);
    const expected = 4.0 * std.math.pi / (0.03 * 0.03);
    try std.testing.expectApproxEqAbs(expected, sigma, 1e-6);
}

test "flat plate scales with A^2" {
    const s1 = try flatPlateNormalIncidenceM2(1.0, 0.03);
    const s2 = try flatPlateNormalIncidenceM2(2.0, 0.03);
    try std.testing.expectApproxEqAbs(4.0, s2 / s1, 1e-9);
}

test "sphere RCS at r = 1 m equals pi m^2" {
    const sigma = try sphereGeometricM2(1.0);
    try std.testing.expectApproxEqAbs(std.math.pi, sigma, 1e-12);
}

test "sphere RCS scales with r^2" {
    const s1 = try sphereGeometricM2(1.0);
    const s2 = try sphereGeometricM2(2.0);
    try std.testing.expectApproxEqAbs(4.0, s2 / s1, 1e-9);
}

test "trihedral corner reflector at a=0.5, lambda=0.03" {
    const sigma = try trihedralCornerReflectorM2(0.5, 0.03);
    const expected = 12.0 * std.math.pi * 0.0625 / (0.03 * 0.03);
    try std.testing.expectApproxEqAbs(expected, sigma, 1e-6);
}

test "trihedral RCS exceeds flat-plate of same A at same lambda" {
    const A = 0.5 * 0.5; // 0.25 m^2 flat area
    const sigma_plate = try flatPlateNormalIncidenceM2(A, 0.03);
    const sigma_corner = try trihedralCornerReflectorM2(0.5, 0.03);
    try std.testing.expect(sigma_corner > sigma_plate);
}

test "radar range scales with sigma^(1/4)" {
    const R1 = try radarRangeM(1.0e4, 1000.0, 0.03, 1.0, 1.0e-13);
    const R2 = try radarRangeM(1.0e4, 1000.0, 0.03, 16.0, 1.0e-13);
    try std.testing.expectApproxEqAbs(2.0, R2 / R1, 1e-6);
}

test "radar range scales with P_t^(1/4)" {
    const R1 = try radarRangeM(1.0e4, 1000.0, 0.03, 1.0, 1.0e-13);
    const R2 = try radarRangeM(1.6e5, 1000.0, 0.03, 1.0, 1.0e-13);
    try std.testing.expectApproxEqAbs(2.0, R2 / R1, 1e-6);
}

test "gain from aperture A=10, lambda=0.03" {
    const G = try gainFromAperture(10.0, 0.03);
    const expected = 4.0 * std.math.pi * 10.0 / (0.03 * 0.03);
    try std.testing.expectApproxEqAbs(expected, G, 1e-6);
}

test "dBsm conversions are inverse" {
    const sigma = 100.0;
    const dbsm = try m2ToDBsm(sigma);
    const back = dBsmToM2(dbsm);
    try std.testing.expectApproxEqAbs(sigma, back, 1e-9);
}

test "0 dBsm = 1 m^2" {
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), dBsmToM2(0.0), 1e-12);
}

test "20 dBsm = 100 m^2" {
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), dBsmToM2(20.0), 1e-9);
}

test "input rejection: zero P_t" {
    try std.testing.expectError(
        Error.NonPositivePower,
        radarRangeM(0.0, 1000.0, 0.03, 1.0, 1.0e-13),
    );
}

test "input rejection: zero lambda" {
    try std.testing.expectError(
        Error.NonPositiveWavelength,
        flatPlateNormalIncidenceM2(1.0, 0.0),
    );
}
