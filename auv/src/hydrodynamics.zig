const std = @import("std");

pub const Error = error{
    NonPositiveLength,
    NonPositiveSpeed,
    NonPositiveDensity,
    NonPositiveViscosity,
    NonPositiveArea,
};

/// Reynolds number based on body length:
///   Re = V L / nu.
pub fn reynoldsNumber(V_mps: f64, L_m: f64, nu_m2_per_s: f64) Error!f64 {
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (!(nu_m2_per_s > 0)) return Error.NonPositiveViscosity;
    return V_mps * L_m / nu_m2_per_s;
}

/// Schlichting turbulent flat-plate friction coefficient (Schlichting
/// 1979): C_F = 0.455 / log10(Re)^2.58.
pub fn schlichtingCF(Re: f64) Error!f64 {
    if (!(Re > 0)) return Error.NonPositiveSpeed;
    return 0.455 / std.math.pow(f64, std.math.log10(Re), 2.58);
}

/// ITTC-57 friction line (also exposed in yard-resistance-zig).
pub fn ittc57CF(Re: f64) Error!f64 {
    if (!(Re > 0)) return Error.NonPositiveSpeed;
    const denom = std.math.log10(Re) - 2.0;
    return 0.075 / (denom * denom);
}

/// Total drag on a streamlined AUV body:
///   D = 0.5 rho V^2 S_w (C_F (1 + k_h) + C_appendage)
/// with (1+k_h) the hull form factor (typ. 1.10-1.20 for slender
/// torpedo bodies).
pub fn totalDragN(
    rho_kg_per_m3: f64,
    V_mps: f64,
    S_w_m2: f64,
    C_F: f64,
    one_plus_k_h: f64,
    C_appendage: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(S_w_m2 > 0)) return Error.NonPositiveArea;
    if (!(C_F > 0)) return Error.NonPositiveSpeed;
    if (!(one_plus_k_h > 0)) return Error.NonPositiveSpeed;
    if (!(C_appendage >= 0)) return Error.NonPositiveArea;
    return 0.5 * rho_kg_per_m3 * V_mps * V_mps * S_w_m2 *
        (C_F * one_plus_k_h + C_appendage);
}

test "Re at V=1 m/s, L=2 m, nu=1.05e-6 m^2/s = 1.905e6" {
    const Re = try reynoldsNumber(1.0, 2.0, 1.05e-6);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 * 2.0 / 1.05e-6), Re, 1e-3);
}

test "Re scales linearly with V" {
    const Re1 = try reynoldsNumber(1.0, 2.0, 1.05e-6);
    const Re2 = try reynoldsNumber(2.0, 2.0, 1.05e-6);
    try std.testing.expectApproxEqAbs(2.0, Re2 / Re1, 1e-9);
}

test "Schlichting C_F decreases with Re" {
    const cF_1e6 = try schlichtingCF(1.0e6);
    const cF_1e7 = try schlichtingCF(1.0e7);
    try std.testing.expect(cF_1e7 < cF_1e6);
}

test "Schlichting and ITTC-57 within 20 % at Re = 1e7" {
    const cF_s = try schlichtingCF(1.0e7);
    const cF_i = try ittc57CF(1.0e7);
    const ratio = cF_s / cF_i;
    try std.testing.expect(ratio > 0.8 and ratio < 1.2);
}

test "ITTC-57 closed form at Re = 1e6: 0.075 / 16" {
    const cF = try ittc57CF(1.0e6);
    try std.testing.expectApproxEqAbs(@as(f64, 0.075 / 16.0), cF, 1e-9);
}

test "total drag closed form" {
    const D = try totalDragN(1025.0, 1.5, 5.0, 0.003, 1.15, 0.0005);
    const expected = 0.5 * 1025.0 * 1.5 * 1.5 * 5.0 * (0.003 * 1.15 + 0.0005);
    try std.testing.expectApproxEqAbs(expected, D, 1e-6);
}

test "drag scales with V^2 (form-factor C_F roughly constant)" {
    const D1 = try totalDragN(1025.0, 1.0, 5.0, 0.003, 1.15, 0.0005);
    const D2 = try totalDragN(1025.0, 2.0, 5.0, 0.003, 1.15, 0.0005);
    // C_F is held constant in this test; only V^2 changes.
    try std.testing.expectApproxEqAbs(4.0, D2 / D1, 1e-9);
}

test "drag scales linearly with wetted surface" {
    const D1 = try totalDragN(1025.0, 1.5, 5.0, 0.003, 1.15, 0.0005);
    const D2 = try totalDragN(1025.0, 1.5, 10.0, 0.003, 1.15, 0.0005);
    try std.testing.expectApproxEqAbs(2.0, D2 / D1, 1e-9);
}

test "drag form factor 1+k_h amplifies friction term" {
    const D_no_k = try totalDragN(1025.0, 1.5, 5.0, 0.003, 1.0, 0.0);
    const D_with_k = try totalDragN(1025.0, 1.5, 5.0, 0.003, 1.20, 0.0);
    try std.testing.expectApproxEqAbs(1.20, D_with_k / D_no_k, 1e-9);
}

test "input rejection: zero V in Re" {
    try std.testing.expectError(Error.NonPositiveSpeed, reynoldsNumber(0.0, 2.0, 1.05e-6));
}

test "input rejection: zero nu" {
    try std.testing.expectError(Error.NonPositiveViscosity, reynoldsNumber(1.0, 2.0, 0.0));
}

test "input rejection: zero S_w" {
    try std.testing.expectError(
        Error.NonPositiveArea,
        totalDragN(1025.0, 1.5, 0.0, 0.003, 1.15, 0.0005),
    );
}
