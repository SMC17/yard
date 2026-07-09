// Model-to-ship resistance extrapolation helpers (ITTC-78 steps 4–7 subset).
//
// Full powering chain lives in yard-ittc78; this module exposes the
// similarity-native C_R transfer and C_T assembly used by spiral workflows.

const std = @import("std");

pub const Error = error{
    NonPositiveReynolds,
    NonPositiveWettedArea,
    NonPositiveSpeed,
    NonPositiveDensity,
};

/// Inputs for a single-speed model test point.
pub const ModelTestPoint = struct {
    L: f64,
    S: f64,
    V: f64,
    nu: f64,
    rho: f64,
    /// Measured total resistance coefficient from tank.
    C_T: f64,
    /// Form factor (1+k) from Prohaska or Holtrop.
    one_plus_k: f64,
};

pub const ShipPoint = struct {
    L: f64,
    S: f64,
    V: f64,
    nu: f64,
    rho: f64,
    /// Frontal area above WL for air drag [m²].
    A_T: f64 = 0.0,
};

pub const ExtrapolationResult = struct {
    C_F_model: f64,
    C_F_ship: f64,
    C_R: f64,
    C_A: f64,
    C_AA: f64,
    C_T_ship: f64,
    R_T_ship: f64,
    P_E_ship: f64,
    rn_model: f64,
    rn_ship: f64,
};

fn cF(rn: f64) Error!f64 {
    if (rn <= 0.0 or rn < 1.0e5) return Error.NonPositiveReynolds;
    const denom = std.math.log10(rn) - 2.0;
    return 0.075 / (denom * denom);
}

fn cA(l_ship: f64) f64 {
    return 0.006 * std.math.pow(f64, l_ship + 100.0, -0.16) - 0.00205;
}

fn cAA(a_t: f64, s: f64) f64 {
    if (s <= 0.0) return 0.0;
    return 0.0001 + 0.00007 * a_t / s;
}

/// ITTC-78 style single-point extrapolation (no propeller / shaft power).
pub fn extrapolateResistance(model: ModelTestPoint, ship: ShipPoint) Error!ExtrapolationResult {
    if (model.S <= 0.0 or ship.S <= 0.0) return Error.NonPositiveWettedArea;
    if (model.V <= 0.0 or ship.V <= 0.0) return Error.NonPositiveSpeed;
    if (model.rho <= 0.0 or ship.rho <= 0.0) return Error.NonPositiveDensity;

    const rn_m = model.V * model.L / model.nu;
    const rn_s = ship.V * ship.L / ship.nu;
    const cf_m = try cF(rn_m);
    const cf_s = try cF(rn_s);
    const c_r = model.C_T - model.one_plus_k * cf_m;
    const c_a = cA(ship.L);
    const c_aa = cAA(ship.A_T, ship.S);
    const c_t_ship = model.one_plus_k * cf_s + c_r + c_a + c_aa;
    const r_t = 0.5 * ship.rho * ship.V * ship.V * ship.S * c_t_ship;
    const p_e = r_t * ship.V;

    return .{
        .C_F_model = cf_m,
        .C_F_ship = cf_s,
        .C_R = c_r,
        .C_A = c_a,
        .C_AA = c_aa,
        .C_T_ship = c_t_ship,
        .R_T_ship = r_t,
        .P_E_ship = p_e,
        .rn_model = rn_m,
        .rn_ship = rn_s,
    };
}

const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "C_R copies from model; C_F evaluated at each Rn" {
    const model: ModelTestPoint = .{
        .L = 6.0,
        .S = 6.5,
        .V = 1.5,
        .nu = 1.139e-6,
        .rho = 1000.0,
        .C_T = 0.0042,
        .one_plus_k = 1.15,
    };
    const ship: ShipPoint = .{
        .L = 150.0,
        .S = 4000.0,
        .V = 7.5,
        .nu = 1.188e-6,
        .rho = 1025.0,
        .A_T = 500.0,
    };
    const r = try extrapolateResistance(model, ship);
    try expectApproxEqAbs(model.C_T - model.one_plus_k * r.C_F_model, r.C_R, 1e-15);
    try std.testing.expect(r.C_F_ship < r.C_F_model);
    try std.testing.expect(r.R_T_ship > 0.0);
    try std.testing.expect(r.P_E_ship > 0.0);
}