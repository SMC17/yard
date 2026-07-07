const std = @import("std");

pub const Error = error{
    NonPositiveLoad,
    NonPositiveArea,
    InvalidMaterial,
};

pub const BlockMaterial = enum {
    /// Pine / Spruce softwood. p_allow ~ 2 MPa.
    Softwood,
    /// Oak / Douglas Fir hardwood. p_allow ~ 5 MPa.
    Hardwood,
    /// Steel keel block. p_allow ~ 50 MPa.
    Steel,
    /// Concrete (precast). p_allow ~ 10 MPa.
    Concrete,
};

pub fn allowablePressurePa(mat: BlockMaterial) f64 {
    return switch (mat) {
        .Softwood => 2.0e6,
        .Hardwood => 5.0e6,
        .Steel => 50.0e6,
        .Concrete => 10.0e6,
    };
}

/// Bearing pressure on a keel block:
///   p = R / A.
pub fn bearingPressurePa(R_n: f64, A_m2: f64) Error!f64 {
    if (!(R_n > 0)) return Error.NonPositiveLoad;
    if (!(A_m2 > 0)) return Error.NonPositiveArea;
    return R_n / A_m2;
}

pub const Verdict = enum {
    /// Bearing pressure below allowable: block can carry the load.
    pass,
    /// Pressure exceeds allowable: block crush risk; larger area
    /// or stronger material required.
    fail,
};

/// Block verdict: compare bearing pressure against material limit.
pub fn pressureVerdict(p_actual_pa: f64, mat: BlockMaterial) Verdict {
    if (p_actual_pa <= allowablePressurePa(mat)) return .pass;
    return .fail;
}

/// Required minimum block area for a given reaction and material:
///   A_min = R / p_allow.
pub fn requiredAreaM2(R_n: f64, mat: BlockMaterial) Error!f64 {
    if (!(R_n > 0)) return Error.NonPositiveLoad;
    const p = allowablePressurePa(mat);
    return R_n / p;
}

test "material allowable pressures" {
    try std.testing.expectApproxEqAbs(@as(f64, 2.0e6), allowablePressurePa(.Softwood), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0e6), allowablePressurePa(.Hardwood), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0e6), allowablePressurePa(.Steel), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0e6), allowablePressurePa(.Concrete), 1e-3);
}

test "bearing pressure: 500 kN over 0.5 m^2 = 1 MPa" {
    const p = try bearingPressurePa(500_000.0, 0.5);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0e6), p, 1e-3);
}

test "bearing pressure scales linearly with R" {
    const p1 = try bearingPressurePa(500_000.0, 0.5);
    const p2 = try bearingPressurePa(1_000_000.0, 0.5);
    try std.testing.expectApproxEqAbs(2.0 * p1, p2, 1e-3);
}

test "bearing pressure inverse with A" {
    const p1 = try bearingPressurePa(500_000.0, 0.5);
    const p2 = try bearingPressurePa(500_000.0, 1.0);
    try std.testing.expectApproxEqAbs(0.5 * p1, p2, 1e-3);
}

test "verdict pass when pressure below allowable" {
    try std.testing.expectEqual(Verdict.pass, pressureVerdict(1.5e6, .Hardwood));
}

test "verdict pass at exactly allowable" {
    try std.testing.expectEqual(Verdict.pass, pressureVerdict(5.0e6, .Hardwood));
}

test "verdict fail when pressure exceeds allowable" {
    try std.testing.expectEqual(Verdict.fail, pressureVerdict(7.0e6, .Hardwood));
}

test "required area: 500 kN on hardwood = 0.1 m^2" {
    const A = try requiredAreaM2(500_000.0, .Hardwood);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), A, 1e-6);
}

test "required area: 5 MN on steel = 0.1 m^2" {
    const A = try requiredAreaM2(5_000_000.0, .Steel);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), A, 1e-6);
}

test "required area on softer wood larger than hardwood" {
    const A_soft = try requiredAreaM2(500_000.0, .Softwood);
    const A_hard = try requiredAreaM2(500_000.0, .Hardwood);
    try std.testing.expect(A_soft > A_hard);
}

test "input rejection: zero load" {
    try std.testing.expectError(Error.NonPositiveLoad, bearingPressurePa(0.0, 0.5));
}

test "input rejection: zero area" {
    try std.testing.expectError(Error.NonPositiveArea, bearingPressurePa(500_000.0, 0.0));
}
