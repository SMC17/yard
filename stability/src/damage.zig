// Lost-buoyancy box-barge damage solver.
//
// For a rectangular box-barge of (L, B, T_intact, D) with N equal
// longitudinal compartments, one of which is fully flooded with
// permeability mu:
//
// At the damaged-condition waterline T_damaged:
//   V_intact = (L_remaining) * B * T_damaged
// The original displaced volume V_0 = L * B * T_intact must equal
// V_intact when permeability of the flooded compartment is mu = 1
// (lost buoyancy treats the flooded compartment as having no buoyancy
// regardless of its actual mu in the canonical formulation; permeability
// here is captured for realism but the algorithm bisects on T_damaged
// such that intact + permeable volume = V_0).
//
// We solve:
//   (L - l_lost) * B * T_damaged + (l_lost * B * T_damaged * (1 - mu)) = L * B * T_intact
//
// where l_lost is the length of the flooded compartment.
//
// Simplified:
//   T_damaged = T_intact * L / (L - mu * l_lost)
//
// For the canonical mu = 1 case:
//   T_damaged = T_intact * L / (L - l_lost)

const std = @import("std");

pub const Error = error{
    FloodingExceedsHullDepth,
    InvalidPermeability,
    NonPositiveDimension,
};

/// Lost-buoyancy damaged-condition waterline for an N-equal-compartment
/// box-barge with one fully-flooded compartment.
///
/// L           total length (m)
/// L_lost      length of the flooded compartment (m)
/// T_intact    intact-condition waterline (m)
/// D           hull depth (m); flooding fails if T_damaged exceeds D
/// mu          permeability of the flooded compartment in [0, 1]
pub fn boxBargeOneCompartment(
    L: f64,
    L_lost: f64,
    T_intact: f64,
    D: f64,
    mu: f64,
) Error!f64 {
    if (mu < 0.0 or mu > 1.0) return Error.InvalidPermeability;
    if (L <= 0.0 or L_lost < 0.0 or T_intact <= 0.0 or D <= 0.0) return Error.NonPositiveDimension;
    if (L_lost >= L) return Error.NonPositiveDimension;

    const T_damaged = T_intact * L / (L - mu * L_lost);
    if (T_damaged >= D) return Error.FloodingExceedsHullDepth;
    return T_damaged;
}

/// Damaged-condition transverse moment of inertia of the intact
/// waterplane for an N-equal-compartment box-barge with one flooded
/// compartment.  I_T = (L - L_lost) * B^3 / 12.
pub fn boxBargeIntactIT(L: f64, L_lost: f64, B: f64) f64 {
    const L_remaining = L - L_lost;
    return L_remaining * B * B * B / 12.0;
}

const expectApproxEqRel = std.testing.expectApproxEqRel;

test "box-barge 1 of 5 compartments flooded matches codex value" {
    // From ~/codex/sources/validation_fixtures.md:
    // L=10, B=4, T_intact=1.5, D=3, 1 of 5 compartments flooded (mu=1).
    // L_lost = 2.0 m. T_damaged = 1.5 * 10 / (10 - 2) = 1.875 m.
    const T_d = try boxBargeOneCompartment(10.0, 2.0, 1.5, 3.0, 1.0);
    try expectApproxEqRel(@as(f64, 1.875), T_d, 1e-12);
}

test "box-barge damage rejects flooding above hull depth" {
    // 4 of 5 compartments flooded gives T_damaged = 1.5 * 10 / (10 - 8) = 7.5 m > D=3.
    try std.testing.expectError(
        Error.FloodingExceedsHullDepth,
        boxBargeOneCompartment(10.0, 8.0, 1.5, 3.0, 1.0),
    );
}

test "box-barge damage rejects invalid permeability" {
    try std.testing.expectError(Error.InvalidPermeability, boxBargeOneCompartment(10.0, 2.0, 1.5, 3.0, -0.1));
    try std.testing.expectError(Error.InvalidPermeability, boxBargeOneCompartment(10.0, 2.0, 1.5, 3.0, 1.1));
}

test "box-barge damage permeability reduces effective lost length" {
    // At mu = 0.5 the flooded compartment retains half its buoyancy.
    // Effective lost length = 0.5 * 2 = 1 m.
    // T_damaged = 1.5 * 10 / (10 - 1) = 1.6667 m.
    const T_d = try boxBargeOneCompartment(10.0, 2.0, 1.5, 3.0, 0.5);
    try expectApproxEqRel(@as(f64, 5.0 / 3.0), T_d, 1e-12);
}

test "boxBargeIntactIT reduces by compartment-length fraction" {
    const I = boxBargeIntactIT(10.0, 2.0, 4.0);
    // Remaining 8 m: I_T = 8 * 64 / 12 = 42.667
    try expectApproxEqRel(@as(f64, 8.0 * 64.0 / 12.0), I, 1e-12);
}
