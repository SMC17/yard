const std = @import("std");

pub const Error = error{
    NegativeResistance,
    UnequalLength,
    NonPositiveThickness,
};

/// Minorsky resistance-factor R_T = sum of (plate thickness t_i)
/// times (damaged plate area A_i). Units: t in m, A in m^2, R_T in
/// m^3 (volumetric damage proxy). Caller supplies parallel arrays.
pub fn resistanceFactorM3(thicknesses_m: []const f64, areas_m2: []const f64) Error!f64 {
    if (thicknesses_m.len != areas_m2.len) return Error.UnequalLength;
    var sum: f64 = 0.0;
    var i: usize = 0;
    while (i < thicknesses_m.len) : (i += 1) {
        if (!(thicknesses_m[i] > 0)) return Error.NonPositiveThickness;
        if (!(areas_m2[i] >= 0)) return Error.NegativeResistance;
        sum += thicknesses_m[i] * areas_m2[i];
    }
    return sum;
}

/// Energy absorbed by structural damage per Minorsky 1959 right-angle
/// ship-to-ship collision regression:
///   E_abs [MJ] = 47.1 R_T + 32.7
/// with R_T expressed in m^3 (volumetric damage proxy).
pub fn absorbedEnergyMJ(R_T_m3: f64) Error!f64 {
    if (!(R_T_m3 >= 0)) return Error.NegativeResistance;
    return 47.1 * R_T_m3 + 32.7;
}

test "Minorsky R_T from a single damaged plate" {
    const t = [_]f64{0.020}; // 20 mm
    const A = [_]f64{ 5.0 }; // 5 m^2
    const R = try resistanceFactorM3(&t, &A);
    try std.testing.expectApproxEqAbs(@as(f64, 0.020 * 5.0), R, 1e-12);
}

test "Minorsky R_T sums multiple plates" {
    const t = [_]f64{ 0.020, 0.015, 0.010 };
    const A = [_]f64{ 5.0, 8.0, 3.0 };
    const R = try resistanceFactorM3(&t, &A);
    const expected = 0.020 * 5.0 + 0.015 * 8.0 + 0.010 * 3.0;
    try std.testing.expectApproxEqAbs(expected, R, 1e-12);
}

test "Minorsky E_abs at R_T = 0 equals the intercept 32.7 MJ" {
    const E = try absorbedEnergyMJ(0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 32.7), E, 1e-12);
}

test "Minorsky E_abs scales with slope 47.1 MJ / m^3" {
    const E1 = try absorbedEnergyMJ(1.0);
    const E2 = try absorbedEnergyMJ(2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 47.1), E2 - E1, 1e-12);
}

test "Minorsky E_abs at R_T = 10 m^3 equals 503.7 MJ" {
    const E = try absorbedEnergyMJ(10.0);
    try std.testing.expectApproxEqAbs(@as(f64, 47.1 * 10.0 + 32.7), E, 1e-12);
}

test "Minorsky rejects unequal-length inputs" {
    const t = [_]f64{ 0.020, 0.015 };
    const A = [_]f64{ 5.0 };
    try std.testing.expectError(Error.UnequalLength, resistanceFactorM3(&t, &A));
}

test "Minorsky rejects non-positive thickness" {
    const t = [_]f64{ 0.020, 0.000 };
    const A = [_]f64{ 5.0, 1.0 };
    try std.testing.expectError(Error.NonPositiveThickness, resistanceFactorM3(&t, &A));
}

test "Minorsky rejects negative R_T input to energy formula" {
    try std.testing.expectError(Error.NegativeResistance, absorbedEnergyMJ(-1.0));
}
