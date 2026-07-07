// ITTC-57 model-ship correlation line (friction coefficient).
//
// C_F = 0.075 / (log10(Rn) - 2)^2
//
// Adopted at the 8th International Towing Tank Conference, Madrid 1957,
// as the model-ship correlation line for converting frictional resistance
// between scales. Applied at both model Rn and ship Rn with the same
// functional form; the model-ship extrapolation chain (ITTC-78) treats
// the wave-pattern residual C_R as Reynolds-independent.
//
// Inputs: Reynolds number Rn = V L / nu (dimensionless).
// Output: friction coefficient C_F (dimensionless).
//
// R_F per unit wetted surface = 0.5 * rho * V^2 * C_F.

const std = @import("std");

pub const Error = error{
    NonPositiveReynolds,
    ReynoldsBelowITTC57Validity,
};

/// Lower bound on Rn below which ITTC-57 (in the model-ship-correlation
/// sense) is not applied. Conventionally the line is treated as valid
/// from Rn = 1e6 upward for naval architecture; lower Rn is laminar /
/// transitional and the Blasius / Schoenherr / laminar formulas apply.
pub const rn_min: f64 = 1.0e5;

/// Coefficient of friction per ITTC-57.
pub fn cF(rn: f64) Error!f64 {
    if (rn <= 0.0) return Error.NonPositiveReynolds;
    if (rn < rn_min) return Error.ReynoldsBelowITTC57Validity;
    const denom = std.math.log10(rn) - 2.0;
    return 0.075 / (denom * denom);
}

/// Frictional resistance per unit wetted surface area per the line.
pub fn rFPerArea(rn: f64, rho: f64, v: f64) Error!f64 {
    const cf = try cF(rn);
    return 0.5 * rho * v * v * cf;
}

/// Reynolds number from speed, length, and kinematic viscosity.
pub fn reynolds(v: f64, l: f64, nu: f64) f64 {
    return v * l / nu;
}

const expectApproxEqAbs = std.testing.expectApproxEqAbs;
const expectApproxEqRel = std.testing.expectApproxEqRel;

test "cF at Rn = 5e6 matches textbook value" {
    // Bertram 2012 + ITTC 7.5-02-03-01.4 worked example:
    // Rn = 5e6 gives C_F = 0.003396 (4 sig fig).
    const cf = try cF(5.0e6);
    try expectApproxEqAbs(@as(f64, 0.003396), cf, 1e-6);
}

test "cF at Rn = 1.5e9 matches textbook value" {
    // Large container ship Rn ~ 1.5e9; ITTC-57 gives 0.001457.
    const cf = try cF(1.5e9);
    try expectApproxEqAbs(@as(f64, 0.001457), cf, 1e-6);
}

test "cF at Rn = 1e6 matches direct evaluation" {
    // log10(1e6) - 2 = 4, so C_F = 0.075 / 16 = 0.0046875 exactly.
    const cf = try cF(1.0e6);
    try expectApproxEqAbs(@as(f64, 0.0046875), cf, 1e-15);
}

test "cF strictly decreases with Reynolds" {
    var rn: f64 = 1.0e6;
    var prev: f64 = try cF(rn);
    rn *= 10.0;
    while (rn <= 1.0e10) : (rn *= 10.0) {
        const cur = try cF(rn);
        try std.testing.expect(cur < prev);
        prev = cur;
    }
}

test "cF positive across the validity range" {
    var rn: f64 = 1.0e5;
    while (rn <= 1.0e10) : (rn *= 2.0) {
        const cf = try cF(rn);
        try std.testing.expect(cf > 0.0);
    }
}

test "cF rejects non-positive Reynolds" {
    try std.testing.expectError(Error.NonPositiveReynolds, cF(0.0));
    try std.testing.expectError(Error.NonPositiveReynolds, cF(-1.0));
}

test "cF rejects Reynolds below validity" {
    try std.testing.expectError(Error.ReynoldsBelowITTC57Validity, cF(1.0));
    try std.testing.expectError(Error.ReynoldsBelowITTC57Validity, cF(1.0e4));
}

test "reynolds returns expected for unit inputs" {
    const rn = reynolds(10.0, 200.0, 1.0e-6);
    try expectApproxEqRel(@as(f64, 2.0e9), rn, 1e-15);
}

test "rFPerArea is positive at typical inputs" {
    const r = try rFPerArea(5.0e6, 1025.0, 8.0);
    try std.testing.expect(r > 0.0);
}

test "rFPerArea scales with V^2 at fixed Rn (not physical but tests dependency)" {
    const r1 = try rFPerArea(1.0e8, 1025.0, 5.0);
    const r2 = try rFPerArea(1.0e8, 1025.0, 10.0);
    // r2 should be 4x r1 because V^2 quadruples.
    try expectApproxEqRel(@as(f64, 4.0), r2 / r1, 1e-12);
}
