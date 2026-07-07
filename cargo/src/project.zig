const std = @import("std");

pub const Error = error{
    NonPositiveMass,
    NonPositiveSwl,
    InvalidAngle,
    NonPositiveLegs,
};

/// Sling-leg tension for a symmetric multi-leg lift:
///   T_per_leg = (m g) / (n * cos(theta))
/// where theta is the angle of each sling from the vertical.
pub fn slingLegTensionN(
    m_kg: f64,
    g_mps2: f64,
    n_legs: u32,
    theta_rad: f64,
) Error!f64 {
    if (!(m_kg > 0)) return Error.NonPositiveMass;
    if (n_legs == 0) return Error.NonPositiveLegs;
    if (!(theta_rad >= 0 and theta_rad < std.math.pi / 2.0)) {
        return Error.InvalidAngle;
    }
    const n_f: f64 = @floatFromInt(n_legs);
    return m_kg * g_mps2 / (n_f * @cos(theta_rad));
}

/// Sling-angle factor (Mode Factor): the multiplier applied to the
/// vertical sling tension to obtain the actual tension. At theta =
/// 60 deg the factor is 2.0; at 45 deg it is sqrt(2).
pub fn slingAngleFactor(theta_rad: f64) Error!f64 {
    if (!(theta_rad >= 0 and theta_rad < std.math.pi / 2.0)) {
        return Error.InvalidAngle;
    }
    return 1.0 / @cos(theta_rad);
}

pub const Verdict = enum { pass, fail };

/// Sling verdict: per-leg tension must remain below the SWL.
pub fn slingVerdict(T_per_leg_n: f64, SWL_per_leg_n: f64) Error!Verdict {
    if (!(SWL_per_leg_n > 0)) return Error.NonPositiveSwl;
    if (T_per_leg_n <= SWL_per_leg_n) return .pass;
    return .fail;
}

/// Cribbing block reaction for an evenly-distributed load on N
/// timber blocks:
///   R_block = m g / N.
pub fn cribReactionN(m_kg: f64, g_mps2: f64, N_blocks: u32) Error!f64 {
    if (!(m_kg > 0)) return Error.NonPositiveMass;
    if (N_blocks == 0) return Error.NonPositiveLegs;
    const n_f: f64 = @floatFromInt(N_blocks);
    return m_kg * g_mps2 / n_f;
}

/// Skidded-load deck-pressure check:
///   p = m g / A
/// against the deck-allowable pressure (typ. 5-10 t/m^2 = 49 - 98
/// kPa for a single-deck cargo ship; 30 t/m^2 = 294 kPa for tank
/// tops).
pub fn deckPressurePa(m_kg: f64, g_mps2: f64, A_skid_m2: f64) Error!f64 {
    if (!(m_kg > 0)) return Error.NonPositiveMass;
    if (!(A_skid_m2 > 0)) return Error.NonPositiveSwl;
    return m_kg * g_mps2 / A_skid_m2;
}

/// Deck-allowable map for common stowage areas.
pub const DeckType = enum {
    /// Weather / tween deck.
    weather_tween,
    /// Cargo-hold tank top.
    tank_top,
    /// Reinforced heavy-lift deck strip.
    heavy_lift_strip,

    pub fn allowablePa(self: DeckType) f64 {
        return switch (self) {
            .weather_tween => 49_000.0,
            .tank_top => 294_000.0,
            .heavy_lift_strip => 1_000_000.0,
        };
    }
};

pub fn deckPressureVerdict(p_pa: f64, deck: DeckType) Verdict {
    if (p_pa <= deck.allowablePa()) return .pass;
    return .fail;
}

test "sling tension: vertical lift (theta = 0) gives m g / n per leg" {
    const T = try slingLegTensionN(4000.0, 9.81, 4, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 4000.0 * 9.81 / 4.0), T, 1e-9);
}

test "sling tension at 60 deg is 2x the vertical tension" {
    const T_vert = try slingLegTensionN(4000.0, 9.81, 4, 0.0);
    const T_60 = try slingLegTensionN(4000.0, 9.81, 4, std.math.pi / 3.0);
    try std.testing.expectApproxEqAbs(2.0 * T_vert, T_60, 1e-9);
}

test "sling tension at 45 deg is sqrt(2) x vertical" {
    const T_vert = try slingLegTensionN(4000.0, 9.81, 4, 0.0);
    const T_45 = try slingLegTensionN(4000.0, 9.81, 4, std.math.pi / 4.0);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 2.0)) * T_vert, T_45, 1e-9);
}

test "sling angle factor at theta = 0 is 1.0" {
    const f = try slingAngleFactor(0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), f, 1e-12);
}

test "sling angle factor at 60 deg is 2.0" {
    const f = try slingAngleFactor(std.math.pi / 3.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), f, 1e-9);
}

test "sling verdict pass when tension <= SWL" {
    try std.testing.expectEqual(Verdict.pass, try slingVerdict(5000.0, 10_000.0));
}

test "sling verdict pass at exact SWL" {
    try std.testing.expectEqual(Verdict.pass, try slingVerdict(10_000.0, 10_000.0));
}

test "sling verdict fail when tension exceeds SWL" {
    try std.testing.expectEqual(Verdict.fail, try slingVerdict(15_000.0, 10_000.0));
}

test "crib reaction: 100 t on 50 blocks = 2 t per block" {
    const R = try cribReactionN(100_000.0, 9.81, 50);
    try std.testing.expectApproxEqAbs(@as(f64, 100_000.0 * 9.81 / 50.0), R, 1e-6);
}

test "deck pressure: 50 t on 4 m^2 = 122.625 kPa" {
    const p = try deckPressurePa(50_000.0, 9.81, 4.0);
    try std.testing.expectApproxEqAbs(@as(f64, 50_000.0 * 9.81 / 4.0), p, 1e-6);
}

test "deck pressure verdict pass on tank top at moderate load" {
    const p = try deckPressurePa(50_000.0, 9.81, 4.0);
    try std.testing.expectEqual(Verdict.pass, deckPressureVerdict(p, .tank_top));
}

test "deck pressure verdict fail on weather deck at heavy load" {
    const p = try deckPressurePa(50_000.0, 9.81, 4.0);
    try std.testing.expectEqual(Verdict.fail, deckPressureVerdict(p, .weather_tween));
}

test "deck allowable ordering: weather < tank top < heavy-lift" {
    try std.testing.expect(DeckType.weather_tween.allowablePa() <
        DeckType.tank_top.allowablePa());
    try std.testing.expect(DeckType.tank_top.allowablePa() <
        DeckType.heavy_lift_strip.allowablePa());
}

test "input rejection: theta >= pi/2" {
    try std.testing.expectError(Error.InvalidAngle, slingLegTensionN(1000.0, 9.81, 4, 2.0));
}

test "input rejection: zero legs" {
    try std.testing.expectError(Error.NonPositiveLegs, slingLegTensionN(1000.0, 9.81, 0, 0.5));
}

test "input rejection: zero skid area" {
    try std.testing.expectError(Error.NonPositiveSwl, deckPressurePa(50_000.0, 9.81, 0.0));
}
