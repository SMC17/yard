const std = @import("std");

pub const Error = error{
    NonPositiveDensity,
    NonPositiveSpeed,
    NonPositiveArea,
    NonPositiveLiftCoefficient,
    NonPositiveWeight,
    NonPositivePressure,
    InvalidCpMin,
};

/// Lift force on a hydrofoil:
///   L = 0.5 rho V^2 S C_L.
pub fn liftN(
    rho_kg_per_m3: f64,
    V_mps: f64,
    S_m2: f64,
    C_L: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(V_mps > 0)) return Error.NonPositiveSpeed;
    if (!(S_m2 > 0)) return Error.NonPositiveArea;
    if (!(C_L > 0)) return Error.NonPositiveLiftCoefficient;
    return 0.5 * rho_kg_per_m3 * V_mps * V_mps * S_m2 * C_L;
}

/// Takeoff (foil-borne) speed when lift equals craft weight:
///   V_TO = sqrt(2 W / (rho S C_L)).
pub fn takeoffSpeedMPerS(
    W_n: f64,
    rho_kg_per_m3: f64,
    S_m2: f64,
    C_L: f64,
) Error!f64 {
    if (!(W_n > 0)) return Error.NonPositiveWeight;
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(S_m2 > 0)) return Error.NonPositiveArea;
    if (!(C_L > 0)) return Error.NonPositiveLiftCoefficient;
    return @sqrt(2.0 * W_n / (rho_kg_per_m3 * S_m2 * C_L));
}

/// Cavitation-onset speed:
///   V_cav = sqrt((p_0 - p_v) / (0.5 rho |C_p_min|)).
/// `C_p_min` is the minimum (most-negative) pressure coefficient on
/// the foil; the kernel takes it as a positive magnitude.
pub fn cavitationOnsetSpeedMPerS(
    p0_pa: f64,
    pv_pa: f64,
    rho_kg_per_m3: f64,
    C_p_min_magnitude: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDensity;
    if (!(p0_pa - pv_pa > 0)) return Error.NonPositivePressure;
    if (!(C_p_min_magnitude > 0)) return Error.InvalidCpMin;
    return @sqrt((p0_pa - pv_pa) / (0.5 * rho_kg_per_m3 * C_p_min_magnitude));
}

pub const Verdict = enum {
    /// V < V_cav: foil operates sub-cavitating.
    sub_cavitating,
    /// V >= V_cav: cavity-flow regime; sub-cavitating foil sections
    /// lose lift; super-cavitating section required.
    cavitating,
};

pub fn cavitationVerdict(V_mps: f64, V_cav_mps: f64) Verdict {
    if (V_mps < V_cav_mps) return .sub_cavitating;
    return .cavitating;
}

/// Span efficiency for a surface-piercing foil: free-surface mirror
/// doubles the effective AR; `e_surface_piercing = 1.0` is a
/// reasonable default for V-foil / dihedral arrangements.
pub const e_surface_piercing: f64 = 1.0;

/// Span efficiency for a fully-submerged horizontal foil: typical
/// e ~ 0.7-0.85 due to tip-vortex induced drag without free-surface
/// mirroring.
pub const e_fully_submerged_default: f64 = 0.85;

/// Lift-to-drag (L/D) given C_L, AR, span efficiency e, and parasite
/// drag coefficient C_D0:
///   C_Di = C_L^2 / (pi AR e)
///   C_D = C_D0 + C_Di
///   L/D = C_L / C_D.
pub fn liftToDragRatio(
    C_L: f64,
    AR: f64,
    e_span: f64,
    C_D0: f64,
) Error!f64 {
    if (!(AR > 0)) return Error.NonPositiveArea;
    if (!(e_span > 0)) return Error.NonPositiveLiftCoefficient;
    if (!(C_L > 0)) return Error.NonPositiveLiftCoefficient;
    if (!(C_D0 >= 0)) return Error.NonPositiveLiftCoefficient;
    const C_Di = C_L * C_L / (std.math.pi * AR * e_span);
    return C_L / (C_D0 + C_Di);
}

test "lift force closed form" {
    const L = try liftN(1025.0, 10.0, 2.0, 0.5);
    // 0.5 * 1025 * 100 * 2 * 0.5 = 51 250 N.
    try std.testing.expectApproxEqAbs(@as(f64, 51_250.0), L, 1e-9);
}

test "lift force scales with V^2" {
    const L1 = try liftN(1025.0, 5.0, 2.0, 0.5);
    const L2 = try liftN(1025.0, 10.0, 2.0, 0.5);
    try std.testing.expectApproxEqAbs(4.0 * L1, L2, 1e-9);
}

test "takeoff speed at W = 50 000 N, rho = 1025, S = 2, C_L = 0.5" {
    const V = try takeoffSpeedMPerS(50_000.0, 1025.0, 2.0, 0.5);
    // V = sqrt(2 * 50000 / (1025 * 2 * 0.5)) = sqrt(100000 / 1025) = sqrt(97.56) = 9.88 m/s.
    const expected = @sqrt(2.0 * 50_000.0 / (1025.0 * 2.0 * 0.5));
    try std.testing.expectApproxEqAbs(expected, V, 1e-9);
}

test "takeoff speed scales with sqrt(W)" {
    const V1 = try takeoffSpeedMPerS(50_000.0, 1025.0, 2.0, 0.5);
    const V2 = try takeoffSpeedMPerS(200_000.0, 1025.0, 2.0, 0.5);
    try std.testing.expectApproxEqAbs(2.0 * V1, V2, 1e-9);
}

test "takeoff speed inversely proportional to sqrt(C_L)" {
    const V1 = try takeoffSpeedMPerS(50_000.0, 1025.0, 2.0, 0.5);
    const V2 = try takeoffSpeedMPerS(50_000.0, 1025.0, 2.0, 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), V2 / V1, 1e-9);
}

test "cavitation onset speed at standard conditions" {
    // p_0 - p_v = 100 000 Pa, rho = 1025, |C_p_min| = 1.0.
    // V = sqrt(100000 / (0.5 * 1025 * 1)) = sqrt(195.12) = 13.97 m/s.
    const V = try cavitationOnsetSpeedMPerS(101_325.0, 1325.0, 1025.0, 1.0);
    const expected = @sqrt(100_000.0 / (0.5 * 1025.0 * 1.0));
    try std.testing.expectApproxEqAbs(expected, V, 1e-9);
}

test "cavitation verdict sub-cavitating below V_cav" {
    try std.testing.expectEqual(Verdict.sub_cavitating, cavitationVerdict(10.0, 14.0));
}

test "cavitation verdict cavitating at and above V_cav" {
    try std.testing.expectEqual(Verdict.cavitating, cavitationVerdict(14.0, 14.0));
    try std.testing.expectEqual(Verdict.cavitating, cavitationVerdict(20.0, 14.0));
}

test "lift-to-drag at C_L = 0.5, AR = 6, e = 0.85, C_D0 = 0.01" {
    const ld = try liftToDragRatio(0.5, 6.0, 0.85, 0.01);
    const C_Di = 0.25 / (std.math.pi * 6.0 * 0.85);
    const expected = 0.5 / (0.01 + C_Di);
    try std.testing.expectApproxEqAbs(expected, ld, 1e-9);
    // Should be in the 15-25 range for a moderate-AR hydrofoil.
    try std.testing.expect(ld > 15.0 and ld < 25.0);
}

test "fully-submerged foil produces lower L/D than ideal mirror" {
    const ld_sub = try liftToDragRatio(0.5, 6.0, e_fully_submerged_default, 0.01);
    const ld_mirror = try liftToDragRatio(0.5, 6.0, e_surface_piercing, 0.01);
    try std.testing.expect(ld_sub < ld_mirror);
}

test "input rejection: zero density" {
    try std.testing.expectError(Error.NonPositiveDensity, liftN(0.0, 10.0, 2.0, 0.5));
}

test "input rejection: zero S" {
    try std.testing.expectError(Error.NonPositiveArea, takeoffSpeedMPerS(50_000.0, 1025.0, 0.0, 0.5));
}

test "input rejection: p_v >= p_0" {
    try std.testing.expectError(Error.NonPositivePressure, cavitationOnsetSpeedMPerS(2000.0, 2300.0, 1025.0, 1.0));
}
