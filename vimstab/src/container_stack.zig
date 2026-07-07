const std = @import("std");

pub const Error = error{
    NonPositiveMass,
    NonPositiveStiffness,
    NonPositiveHeight,
    InvalidRollAngle,
};

/// Total mass of an N-tier container stack with per-tier masses.
pub fn totalStackMassKg(tier_masses_kg: []const f64) Error!f64 {
    if (tier_masses_kg.len == 0) return Error.NonPositiveMass;
    var sum: f64 = 0.0;
    for (tier_masses_kg) |m| {
        if (!(m > 0)) return Error.NonPositiveMass;
        sum += m;
    }
    return sum;
}

/// Lateral acceleration at the stack midpoint:
///   a_lateral = g sin phi + a_y_cg
/// where phi is the instantaneous roll angle [rad] and a_y_cg is the
/// lateral acceleration at the stack CG from heave-roll-pitch
/// coupling.
pub fn lateralAccelerationMPS2(
    g_mps2: f64,
    phi_rad: f64,
    a_y_cg_mps2: f64,
) Error!f64 {
    if (!(phi_rad >= -std.math.pi / 2.0 and phi_rad <= std.math.pi / 2.0)) {
        return Error.InvalidRollAngle;
    }
    return g_mps2 * @sin(phi_rad) + a_y_cg_mps2;
}

/// Total lateral force on a container stack:
///   F_lat = m_total * a_lateral.
pub fn lateralForceN(m_total_kg: f64, a_lateral_mps2: f64) Error!f64 {
    if (!(m_total_kg > 0)) return Error.NonPositiveMass;
    return m_total_kg * a_lateral_mps2;
}

/// Racking deflection of the stack under lateral force:
///   delta = F / k_total.
/// k_total combines lashing-rod stiffness, container corner-post
/// stiffness, and twistlock compliance.
pub fn rackingDeflectionM(F_lat_n: f64, k_total_n_per_m: f64) Error!f64 {
    if (!(k_total_n_per_m > 0)) return Error.NonPositiveStiffness;
    return F_lat_n / k_total_n_per_m;
}

pub const Verdict = enum {
    /// Racking deflection <= permissible: stack arrangement passes
    /// MSC.252(83) screening.
    pass,
    /// Deflection exceeds permissible: redesign / re-lash required.
    fail,
};

/// Compare racking deflection against an allowable limit (typ. 25 mm
/// for 8 ft 6 in / 9 ft 6 in standard ISO containers per IMO CSS
/// Code).
pub fn deflectionVerdict(
    delta_m: f64,
    delta_allow_m: f64,
) Error!Verdict {
    if (!(delta_allow_m > 0)) return Error.NonPositiveStiffness;
    if (!(delta_m >= 0)) return Error.NonPositiveStiffness;
    if (delta_m <= delta_allow_m) return .pass;
    return .fail;
}

test "total stack mass: 3-tier 20-tonne each = 60 t" {
    const tiers = [_]f64{ 20_000.0, 20_000.0, 20_000.0 };
    const m = try totalStackMassKg(&tiers);
    try std.testing.expectApproxEqAbs(@as(f64, 60_000.0), m, 1e-12);
}

test "lateral acceleration at phi=0, a_y=0 is zero" {
    const a = try lateralAccelerationMPS2(9.81, 0.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), a, 1e-12);
}

test "lateral acceleration at phi=30 deg, a_y=0 is g/2" {
    const a = try lateralAccelerationMPS2(9.81, std.math.pi / 6.0, 0.0);
    try std.testing.expectApproxEqAbs(9.81 / 2.0, a, 1e-9);
}

test "lateral acceleration at phi=0, a_y=2 m/s^2 equals 2 m/s^2" {
    const a = try lateralAccelerationMPS2(9.81, 0.0, 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), a, 1e-12);
}

test "lateral force scales linearly with mass" {
    const F1 = try lateralForceN(60_000.0, 3.0);
    const F2 = try lateralForceN(120_000.0, 3.0);
    try std.testing.expectApproxEqAbs(2.0 * F1, F2, 1e-9);
}

test "lateral force at 60 t and 3 m/s^2 equals 180 kN" {
    const F = try lateralForceN(60_000.0, 3.0);
    try std.testing.expectApproxEqAbs(@as(f64, 180_000.0), F, 1e-9);
}

test "racking deflection at F=180 kN, k=10 MN/m = 18 mm" {
    const d = try rackingDeflectionM(180_000.0, 10_000_000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.018), d, 1e-12);
}

test "racking deflection inversely proportional to stiffness" {
    const d1 = try rackingDeflectionM(180_000.0, 10_000_000.0);
    const d2 = try rackingDeflectionM(180_000.0, 20_000_000.0);
    try std.testing.expectApproxEqAbs(0.5 * d1, d2, 1e-12);
}

test "verdict pass when delta <= permissible" {
    try std.testing.expectEqual(Verdict.pass, try deflectionVerdict(0.018, 0.025));
}

test "verdict pass at exactly permissible" {
    try std.testing.expectEqual(Verdict.pass, try deflectionVerdict(0.025, 0.025));
}

test "verdict fail when delta > permissible" {
    try std.testing.expectEqual(Verdict.fail, try deflectionVerdict(0.030, 0.025));
}

test "input rejection: zero stiffness" {
    try std.testing.expectError(Error.NonPositiveStiffness, rackingDeflectionM(100_000.0, 0.0));
}

test "input rejection: phi > pi/2" {
    try std.testing.expectError(Error.InvalidRollAngle, lateralAccelerationMPS2(9.81, 2.0, 0.0));
}

test "input rejection: empty tier list" {
    const tiers: []const f64 = &[_]f64{};
    try std.testing.expectError(Error.NonPositiveMass, totalStackMassKg(tiers));
}
