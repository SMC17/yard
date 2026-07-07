const std = @import("std");

pub const Error = error{
    NonPositiveLength,
    NonPositiveDiameter,
    InvalidHollowDiameter,
    NonPositiveShearModulus,
};

/// Polar moment of inertia of a solid circular shaft:
///   J = pi D^4 / 32 [m^4].
pub fn polarSolidM4(D_m: f64) Error!f64 {
    if (!(D_m > 0)) return Error.NonPositiveDiameter;
    const D2 = D_m * D_m;
    return std.math.pi * D2 * D2 / 32.0;
}

/// Polar moment of inertia of a hollow circular shaft:
///   J = pi (D_o^4 - D_i^4) / 32 [m^4].
pub fn polarHollowM4(D_outer_m: f64, D_inner_m: f64) Error!f64 {
    if (!(D_outer_m > 0)) return Error.NonPositiveDiameter;
    if (!(D_inner_m >= 0)) return Error.NonPositiveDiameter;
    if (!(D_inner_m < D_outer_m)) return Error.InvalidHollowDiameter;
    const Do2 = D_outer_m * D_outer_m;
    const Di2 = D_inner_m * D_inner_m;
    return std.math.pi * (Do2 * Do2 - Di2 * Di2) / 32.0;
}

/// Torsional stiffness of a uniform shaft segment:
///   k = G J / L [N m / rad].
pub fn torsionalStiffnessNmPerRad(G_pa: f64, J_m4: f64, L_m: f64) Error!f64 {
    if (!(G_pa > 0)) return Error.NonPositiveShearModulus;
    if (!(J_m4 > 0)) return Error.NonPositiveDiameter;
    if (!(L_m > 0)) return Error.NonPositiveLength;
    return G_pa * J_m4 / L_m;
}

/// Polar mass moment of inertia of a solid cylindrical shaft segment:
///   I = (1/2) m R^2 with m = rho pi R^2 L = (rho pi D^2 L / 4)
///   so I = rho pi D^4 L / 32.
pub fn polarMassInertiaSolidKgm2(D_m: f64, L_m: f64, rho_kg_per_m3: f64) Error!f64 {
    if (!(D_m > 0)) return Error.NonPositiveDiameter;
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveShearModulus;
    const D2 = D_m * D_m;
    return rho_kg_per_m3 * std.math.pi * D2 * D2 * L_m / 32.0;
}

test "solid polar J: D = 0.5 m" {
    const J = try polarSolidM4(0.5);
    const expected = std.math.pi * 0.0625 / 32.0;
    try std.testing.expectApproxEqAbs(expected, J, 1e-15);
}

test "solid polar J scales with D^4" {
    const J1 = try polarSolidM4(0.3);
    const J2 = try polarSolidM4(0.6);
    try std.testing.expectApproxEqAbs(@as(f64, 16.0), J2 / J1, 1e-9);
}

test "hollow polar J for D_o=0.5, D_i=0.3" {
    const J = try polarHollowM4(0.5, 0.3);
    const expected = std.math.pi * (0.0625 - 0.0081) / 32.0;
    try std.testing.expectApproxEqAbs(expected, J, 1e-15);
}

test "hollow polar J equals solid when D_i = 0" {
    const Js = try polarSolidM4(0.5);
    const Jh = try polarHollowM4(0.5, 0.0);
    try std.testing.expectApproxEqAbs(Js, Jh, 1e-15);
}

test "torsional stiffness: doubling L halves k" {
    const J = try polarSolidM4(0.5);
    const k1 = try torsionalStiffnessNmPerRad(80e9, J, 5.0);
    const k2 = try torsionalStiffnessNmPerRad(80e9, J, 10.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), k2 / k1, 1e-12);
}

test "torsional stiffness numerical example" {
    // G = 80 GPa, D = 0.5 m, L = 5 m -> k.
    const J = try polarSolidM4(0.5);
    const k = try torsionalStiffnessNmPerRad(80e9, J, 5.0);
    // k = 80e9 * pi * 0.0625 / 32 / 5 = 80e9 * 6.135e-3 / 5 = 9.817e7 Nm/rad.
    try std.testing.expect(k > 9.8e7 and k < 1.0e8);
}

test "polar mass inertia: doubling L doubles I" {
    const I1 = try polarMassInertiaSolidKgm2(0.5, 1.0, 7850.0);
    const I2 = try polarMassInertiaSolidKgm2(0.5, 2.0, 7850.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), I2 / I1, 1e-12);
}

test "input rejection: zero diameter" {
    try std.testing.expectError(Error.NonPositiveDiameter, polarSolidM4(0.0));
}

test "input rejection: hollow with D_i >= D_o" {
    try std.testing.expectError(Error.InvalidHollowDiameter, polarHollowM4(0.5, 0.5));
}
