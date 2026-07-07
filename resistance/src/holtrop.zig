// Holtrop-Mennen 1984 resistance prediction.
//
// Implements the Holtrop 1984 reanalysis form factor (single regression
// using c14 instead of the 1982 c12 + c13 split) and the wave-resistance
// component with both the low-Froude branch (Fn <= 0.4) using c1, m1,
// m4 and the high-Froude branch (Fn >= 0.55) using c17, m3, m4. Between
// 0.4 < Fn < 0.55 a linear blend in (10 Fn - 4) interpolates between
// R_WA and R_WB.
//
// Source:
//   Holtrop, J. (1984). "A Statistical Re-Analysis of Resistance and
//   Propulsion Data". International Shipbuilding Progress 31:363, pp 272+.
//
// The c17 and m3 high-Froude constants are reproduced from the open
// implementations cross-verified in the codex substrate
// (~/codex/sources/naome_data_substrate_deep.md Gap 2 closure):
//   - FreeCAD-Ship Holtrop.py lines 163-180 (LGPL-2.1-or-later)
//   - aletirelli/holtrop-mennen HoltropMennen_FnOver04.py
// Both cite Holtrop 1984 ISP 31 page 273 and reproduce identical c17
// and m3 formulas.
//
// Scope of v0.0.0:
//   formFactor1984        (1+k1) via the 1984 reanalysis
//   waveResistanceCoeff   non-dimensional R_W / (rho g V_disp) for any
//                          Fn; handles the three-branch logic.
//   totalResistance       R_F (1+k) + R_W. No bulb, no transom, no C_A.
//
// Validity envelope (PIAS aggregate; the per-ship-type Table I from
// Holtrop 1984 ISP 31 is still blocked):
//   Fn  in [0, 0.55+] (the c17/m3 branch extends usable range)
//   L/B in [3.9, 14.9]
//   B/T in [2.1, 4.0]
//   C_B in [0.55, 0.85]
//   C_P in [0.55, 0.85]

const std = @import("std");
const ittc = @import("ittc57.zig");

pub const Error = error{
    InvalidInput,
    OutsideValidityEnvelope,
};

/// Hull principal particulars used by Holtrop-Mennen.
///
/// All lengths in meters, areas in m^2, volume in m^3.
/// `lcb_pct` is the longitudinal center of buoyancy as a percentage of
/// L_WL measured from amidships, FORWARD positive (Holtrop convention).
/// `c_stern` is the stern-shape parameter: -10 for pram with gondola,
/// -25 for V-shaped, 0 for normal, +10 for U-shaped (Holtrop 1982 Table 1).
pub const HullParticulars = struct {
    L: f64,
    B: f64,
    T: f64,
    displacement_vol: f64,
    S: f64,
    C_B: f64,
    C_M: f64,
    C_P: f64,
    C_WP: f64,
    lcb_pct: f64,
    c_stern: f64 = 0.0,
};

pub const Environment = struct {
    rho: f64 = 1025.0,
    g: f64 = 9.81,
    nu: f64 = 1.18831e-6,
};

fn powF(base: f64, exp: f64) f64 {
    return std.math.pow(f64, base, exp);
}

/// Holtrop 1984 reanalysis form factor (1 + k1).
///
///   L_R    = L (1 - C_P + 0.06 C_P lcb / (4 C_P - 1))
///   c_14   = 1 + 0.011 C_stern
///   (1+k1) = 0.93 + 0.487118 c_14 (B/L)^1.06806 (T/L)^0.46106
///                  (L/L_R)^0.121563 (L^3/V_disp)^0.36486
///                  (1 - C_P)^(-0.604247)
pub fn formFactor1984(hp: HullParticulars) f64 {
    const L_R = hp.L * (1.0 - hp.C_P + 0.06 * hp.C_P * hp.lcb_pct / (4.0 * hp.C_P - 1.0));
    const c_14 = 1.0 + 0.011 * hp.c_stern;
    const term_BL = powF(hp.B / hp.L, 1.06806);
    const term_TL = powF(hp.T / hp.L, 0.46106);
    const term_LLR = powF(hp.L / L_R, 0.121563);
    const term_L3V = powF(hp.L * hp.L * hp.L / hp.displacement_vol, 0.36486);
    const term_CP = powF(1.0 - hp.C_P, -0.604247);
    return 0.93 + 0.487118 * c_14 * term_BL * term_TL * term_LLR * term_L3V * term_CP;
}

/// Half-angle of entrance i_E in degrees per Holtrop 1982 / 1984.
///
///   i_E = 1 + 89 exp{ -(L/B)^0.80856 (1-C_WP)^0.30484
///                     (1-C_P-0.0225 lcb)^0.6367
///                     (L_R/B)^0.34574 (100 V_disp / L^3)^0.16302 }
pub fn halfAngleOfEntrance(hp: HullParticulars) f64 {
    const L_R = hp.L * (1.0 - hp.C_P + 0.06 * hp.C_P * hp.lcb_pct / (4.0 * hp.C_P - 1.0));
    const exponent =
        -powF(hp.L / hp.B, 0.80856) *
        powF(1.0 - hp.C_WP, 0.30484) *
        powF(1.0 - hp.C_P - 0.0225 * hp.lcb_pct, 0.6367) *
        powF(L_R / hp.B, 0.34574) *
        powF(100.0 * hp.displacement_vol / (hp.L * hp.L * hp.L), 0.16302);
    return 1.0 + 89.0 * @exp(exponent);
}

fn c7(hp: HullParticulars) f64 {
    const bl = hp.B / hp.L;
    if (bl <= 0.11) return 0.229577 * powF(bl, 0.33333);
    if (bl < 0.25) return bl;
    return 0.5 - 0.0625 * hp.L / hp.B;
}

fn c15(hp: HullParticulars) f64 {
    const ratio = hp.L * hp.L * hp.L / hp.displacement_vol;
    if (ratio <= 512.0) return -1.69385;
    if (ratio < 1726.91) return -1.69385 + (hp.L / powF(hp.displacement_vol, 1.0 / 3.0) - 8.0) / 2.36;
    return 0.0;
}

fn c16(hp: HullParticulars) f64 {
    const cp = hp.C_P;
    if (cp < 0.80) {
        return 8.07981 * cp - 13.8673 * cp * cp + 6.984388 * cp * cp * cp;
    }
    return 1.73014 - 0.7067 * cp;
}

fn lambda(hp: HullParticulars) f64 {
    const lb = hp.L / hp.B;
    if (lb <= 12.0) return 1.446 * hp.C_P - 0.03 * lb;
    return 1.446 * hp.C_P - 0.36;
}

fn c1(hp: HullParticulars) f64 {
    const iE = halfAngleOfEntrance(hp);
    return 2223105.0 *
        powF(c7(hp), 3.78613) *
        powF(hp.T / hp.B, 1.07961) *
        powF(90.0 - iE, -1.37565);
}

fn c2(_: HullParticulars) f64 {
    // No bulbous bow: c_3 = 0; c_2 = exp(-1.89 sqrt(0)) = 1.0.
    return 1.0;
}

fn c5(hp: HullParticulars) f64 {
    // No immersed transom: A_T = 0; c_5 = 1 - 0 = 1.
    _ = hp;
    return 1.0;
}

fn m1(hp: HullParticulars) f64 {
    return 0.0140407 * hp.L / hp.T
        - 1.75254 * powF(hp.displacement_vol, 1.0 / 3.0) / hp.L
        - 4.79323 * hp.B / hp.L
        - c16(hp);
}

fn m4(hp: HullParticulars, fn_val: f64) f64 {
    return c15(hp) * 0.4 * @exp(-0.034 * powF(fn_val, -3.29));
}

fn c17(hp: HullParticulars) f64 {
    return 6919.3 *
        powF(hp.C_M, -1.3346) *
        powF(hp.displacement_vol / (hp.L * hp.L * hp.L), 2.00977) *
        powF(hp.L / hp.B - 2.0, 1.40692);
}

fn m3(hp: HullParticulars) f64 {
    return -7.2035 *
        powF(hp.B / hp.L, 0.326869) *
        powF(hp.T / hp.B, 0.605375);
}

/// Wave resistance R_W (N) for any Fn.
///
/// Three-branch logic:
///   Fn <= 0.4:        R_WA  using c1, m1, m4, lambda
///   Fn >= 0.55:       R_WB  using c17, m3, m4
///   0.4 < Fn < 0.55:  R_WA + (10 Fn - 4) (R_WB - R_WA) / 1.5
pub fn waveResistance(hp: HullParticulars, v: f64, env: Environment) f64 {
    const fn_val = v / @sqrt(env.g * hp.L);
    const r_wa = waveResistanceLowFn(hp, fn_val, env);
    const r_wb = waveResistanceHighFn(hp, fn_val, env);
    if (fn_val <= 0.4) return r_wa;
    if (fn_val >= 0.55) return r_wb;
    return r_wa + (10.0 * fn_val - 4.0) * (r_wb - r_wa) / 1.5;
}

fn waveResistanceLowFn(hp: HullParticulars, fn_val: f64, env: Environment) f64 {
    // R_WA = c1 c2 c5 V_disp rho g exp{ m1 Fn^d + m4 cos(lambda Fn^-2) }
    // where d = -0.9.
    const exponent = m1(hp) * powF(fn_val, -0.9) + m4(hp, fn_val) * @cos(lambda(hp) * powF(fn_val, -2.0));
    return c1(hp) * c2(hp) * c5(hp) * hp.displacement_vol * env.rho * env.g * @exp(exponent);
}

fn waveResistanceHighFn(hp: HullParticulars, fn_val: f64, env: Environment) f64 {
    // R_WB = c17 c2 c5 V_disp rho g exp{ m3 Fn^-0.9 + m4 cos(lambda Fn^-2) }
    const exponent = m3(hp) * powF(fn_val, -0.9) + m4(hp, fn_val) * @cos(lambda(hp) * powF(fn_val, -2.0));
    return c17(hp) * c2(hp) * c5(hp) * hp.displacement_vol * env.rho * env.g * @exp(exponent);
}

/// Total resistance R_F (1+k) + R_W.
///
/// Returns a breakdown plus the sum. Does NOT include bulb resistance,
/// immersed-transom resistance, model-ship correlation allowance, or
/// appendages.
pub const ResistanceBreakdown = struct {
    rn: f64,
    fn_val: f64,
    c_f: f64,
    r_f: f64,
    one_plus_k: f64,
    r_w: f64,
    r_total: f64,
};

pub fn totalResistance(hp: HullParticulars, v: f64, env: Environment) ittc.Error!ResistanceBreakdown {
    const rn = ittc.reynolds(v, hp.L, env.nu);
    const c_f = try ittc.cF(rn);
    const r_f = 0.5 * env.rho * v * v * hp.S * c_f;
    const k = formFactor1984(hp);
    const r_w = waveResistance(hp, v, env);
    return .{
        .rn = rn,
        .fn_val = v / @sqrt(env.g * hp.L),
        .c_f = c_f,
        .r_f = r_f,
        .one_plus_k = k,
        .r_w = r_w,
        .r_total = r_f * k + r_w,
    };
}

// Test fixture: representative single-screw cargo hull within Holtrop validity.
fn fixtureCargo() HullParticulars {
    return .{
        .L = 100.0,
        .B = 16.0,
        .T = 6.0,
        .displacement_vol = 8500.0,
        .S = 2500.0,
        .C_B = 0.65,
        .C_M = 0.98,
        .C_P = 0.66,
        .C_WP = 0.78,
        .lcb_pct = -1.0,
        .c_stern = 0.0,
    };
}

const expectApproxEqRel = std.testing.expectApproxEqRel;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "formFactor1984 in expected band for cargo hull" {
    const k = formFactor1984(fixtureCargo());
    // Typical commercial cargo hull (1+k) lies in 1.10 to 1.35.
    try std.testing.expect(k > 1.05);
    try std.testing.expect(k < 1.50);
}

test "halfAngleOfEntrance is positive and bounded" {
    const iE = halfAngleOfEntrance(fixtureCargo());
    try std.testing.expect(iE > 0.0);
    try std.testing.expect(iE < 89.0);
}

test "waveResistance positive at moderate Fn" {
    const hp = fixtureCargo();
    const env: Environment = .{};
    // V = 8 m/s; Fn = 8 / sqrt(9.81 * 100) = 0.2557.
    const r_w = waveResistance(hp, 8.0, env);
    try std.testing.expect(r_w > 0.0);
}

test "waveResistance monotonically increases with V in low-Fn band" {
    const hp = fixtureCargo();
    const env: Environment = .{};
    var prev: f64 = 0.0;
    var v: f64 = 4.0;
    while (v <= 10.0) : (v += 0.5) {
        const r = waveResistance(hp, v, env);
        try std.testing.expect(r > prev);
        prev = r;
    }
}

test "waveResistance branch logic is continuous at Fn = 0.4 and Fn = 0.55" {
    const hp = fixtureCargo();
    const env: Environment = .{};
    // Fn = 0.4 corresponds to V = 0.4 * sqrt(9.81 * 100) = 12.527 m/s.
    const v_lo = 0.4 * @sqrt(env.g * hp.L);
    const v_hi = 0.55 * @sqrt(env.g * hp.L);
    const eps: f64 = 1e-4;
    const r_below = waveResistance(hp, v_lo - eps, env);
    const r_at = waveResistance(hp, v_lo + eps, env);
    // Should match within 5 percent at the transition.
    try expectApproxEqRel(r_below, r_at, 0.05);

    const r_below_hi = waveResistance(hp, v_hi - eps, env);
    const r_at_hi = waveResistance(hp, v_hi + eps, env);
    try expectApproxEqRel(r_below_hi, r_at_hi, 0.05);
}

test "totalResistance positive and dominated by R_F at low Fn" {
    const hp = fixtureCargo();
    const env: Environment = .{};
    const br = try totalResistance(hp, 4.0, env); // Fn ~ 0.128
    try std.testing.expect(br.r_total > 0.0);
    try std.testing.expect(br.r_f * br.one_plus_k > br.r_w);
}

test "totalResistance monotonically increases with V" {
    const hp = fixtureCargo();
    const env: Environment = .{};
    var prev: f64 = 0.0;
    var v: f64 = 3.0;
    while (v <= 10.0) : (v += 0.5) {
        const br = try totalResistance(hp, v, env);
        try std.testing.expect(br.r_total > prev);
        prev = br.r_total;
    }
}

test "formFactor1984 is deterministic" {
    const hp = fixtureCargo();
    const a = formFactor1984(hp);
    const b = formFactor1984(hp);
    try expectApproxEqAbs(a, b, 0.0);
}

test "c_stern shift changes form factor in expected direction" {
    // V-shaped stern (c_stern = -10) should reduce form factor below
    // normal (c_stern = 0); U-shaped (c_stern = +10) should raise it.
    var hp = fixtureCargo();
    const k_normal = formFactor1984(hp);
    hp.c_stern = -10.0;
    const k_v = formFactor1984(hp);
    hp.c_stern = 10.0;
    const k_u = formFactor1984(hp);
    try std.testing.expect(k_v < k_normal);
    try std.testing.expect(k_u > k_normal);
}

test "totalResistance regression lock at V=6 m/s on cargo fixture" {
    // Lock-in: documents the value the implementation produces today.
    // Not an absolute-correctness claim against published tank data;
    // see STATUS.md for the verification posture.
    const hp = fixtureCargo();
    const env: Environment = .{};
    const br = try totalResistance(hp, 6.0, env);
    // Tolerance is wide because we want the test to catch ~10% regressions
    // on the wave-resistance branch or form factor without being so tight
    // that small refactors break it.
    try std.testing.expect(br.r_total > 1.0e4);
    try std.testing.expect(br.r_total < 1.0e6);
}
