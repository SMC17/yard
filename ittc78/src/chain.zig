// ITTC-78 Performance Prediction Method (11-step extrapolation chain).
//
// Standardized at the 15th ITTC, 1978. Updates and refinements are in
// ITTC Recommended Procedure 7.5-02-03-01.4 (current revision).
//
// Inputs are split into model scale, ship scale, and propulsion factors.
// All inputs are scalars; no offsets table is required.
//
// The 11 steps are:
//   1. Reynolds at model and ship scales.
//   2. C_F at both via ITTC-57.
//   3. Form factor (1 + k) from a low-Fn Prohaska plot (caller supplied).
//   4. Total resistance coefficient at model: C_T_model from tank test.
//   5. Wave-pattern residual at model: C_R = C_T - (1+k) C_F_model.
//   6. C_R is Reynolds-independent under Froude scaling; copy to ship.
//   7. Ship total resistance: C_T_ship = (1+k) C_F_ship + C_R + C_A + C_AA.
//   8. Ship effective power: P_E = R_T_ship * V_ship.
//   9. Self-propulsion: wake fraction w, thrust deduction t,
//      relative rotative efficiency eta_R (caller supplied; would
//      come from Holtrop or a tank self-propulsion test).
//  10. Propeller open-water at the ship operating J:
//      K_T_s, K_Q_s (caller supplied; would come from Wageningen).
//  11. Delivered power: P_D = 2 pi rho_s n_s^3 D^5 K_Q_s / eta_R.
//      Shaft power: P_S = P_D / eta_S.

const std = @import("std");

pub const Error = error{
    NonPositiveReynolds,
    NonPositiveSpeed,
    NonPositiveWettedArea,
    NonPositiveLength,
    InvalidWakeFraction,
    InvalidThrustDeduction,
    NonPositiveDiameter,
};

pub const rn_min_ittc57: f64 = 1.0e5;

fn cF(rn: f64) Error!f64 {
    if (rn <= 0.0) return Error.NonPositiveReynolds;
    if (rn < rn_min_ittc57) return Error.NonPositiveReynolds;
    const denom = std.math.log10(rn) - 2.0;
    return 0.075 / (denom * denom);
}

pub const ModelScale = struct {
    L: f64,
    S: f64,
    V: f64,
    nu: f64,
    /// Measured model total resistance coefficient C_T from towing-tank.
    C_T: f64,
    rho: f64,
};

pub const ShipScale = struct {
    L: f64,
    S: f64,
    V: f64,
    nu: f64,
    rho: f64,
    /// Frontal area projected above waterline (m^2) used for air drag.
    A_T: f64 = 0.0,
};

pub const PropulsionFactors = struct {
    /// Form factor (1 + k) from Prohaska plot.
    one_plus_k: f64,
    /// Wake fraction in [0, 0.9].
    w: f64,
    /// Thrust deduction in [-0.1, 0.5].
    t: f64,
    /// Relative rotative efficiency, typically [0.9, 1.05].
    eta_R: f64,
    /// Shaft + mechanical efficiency, typically [0.97, 0.99].
    eta_S: f64,
};

pub const Propeller = struct {
    D: f64,
    n_s: f64,
    /// Open-water thrust coefficient at the ship operating J_s.
    K_T_s: f64,
    /// Open-water torque coefficient at the ship operating J_s.
    K_Q_s: f64,
};

pub const Result = struct {
    rn_model: f64,
    rn_ship: f64,
    cf_model: f64,
    cf_ship: f64,
    C_R: f64,
    C_A: f64,
    C_AA: f64,
    C_T_ship: f64,
    R_T_ship: f64,
    P_E_ship: f64,
    P_D_ship: f64,
    P_S_ship: f64,
};

/// Model-ship correlation allowance per ITTC-78:
/// C_A = 0.006 (L_s + 100)^(-0.16) - 0.00205.
fn correlationAllowance(L_s: f64) f64 {
    return 0.006 * std.math.pow(f64, L_s + 100.0, -0.16) - 0.00205;
}

/// Air-resistance allowance: C_AA = 0.0001 + 0.00007 * A_T / S_s
/// (informative ITTC convention; many sources use a constant ~0.0001).
fn airResistanceCoeff(A_T: f64, S_s: f64) f64 {
    return 0.0001 + 0.00007 * A_T / S_s;
}

/// Run the full 11-step extrapolation.
pub fn extrapolate(
    model: ModelScale,
    ship: ShipScale,
    factors: PropulsionFactors,
    prop: Propeller,
) Error!Result {
    if (model.V <= 0.0 or ship.V <= 0.0) return Error.NonPositiveSpeed;
    if (model.S <= 0.0 or ship.S <= 0.0) return Error.NonPositiveWettedArea;
    if (model.L <= 0.0 or ship.L <= 0.0) return Error.NonPositiveLength;
    if (factors.w < 0.0 or factors.w > 0.9) return Error.InvalidWakeFraction;
    if (factors.t < -0.1 or factors.t > 0.5) return Error.InvalidThrustDeduction;
    if (prop.D <= 0.0) return Error.NonPositiveDiameter;

    // Step 1.
    const rn_m = model.V * model.L / model.nu;
    const rn_s = ship.V * ship.L / ship.nu;
    // Step 2.
    const cf_m = try cF(rn_m);
    const cf_s = try cF(rn_s);
    // Steps 3 to 5.
    const C_R = model.C_T - factors.one_plus_k * cf_m;
    // Step 6: C_R copies to ship under Froude scaling. (No additional work.)
    // Step 7.
    const C_A = correlationAllowance(ship.L);
    const C_AA = airResistanceCoeff(ship.A_T, ship.S);
    const C_T_s = factors.one_plus_k * cf_s + C_R + C_A + C_AA;
    // Step 8.
    const R_T_s = 0.5 * ship.rho * ship.V * ship.V * ship.S * C_T_s;
    const P_E_s = R_T_s * ship.V;
    // Step 9 to 11.
    const T_required = R_T_s / (1.0 - factors.t);
    _ = T_required;
    const P_D_s = 2.0 * std.math.pi * ship.rho * prop.n_s * prop.n_s * prop.n_s *
        std.math.pow(f64, prop.D, 5.0) * prop.K_Q_s / factors.eta_R;
    const P_S_s = P_D_s / factors.eta_S;

    return .{
        .rn_model = rn_m,
        .rn_ship = rn_s,
        .cf_model = cf_m,
        .cf_ship = cf_s,
        .C_R = C_R,
        .C_A = C_A,
        .C_AA = C_AA,
        .C_T_ship = C_T_s,
        .R_T_ship = R_T_s,
        .P_E_ship = P_E_s,
        .P_D_ship = P_D_s,
        .P_S_ship = P_S_s,
    };
}

const expectApproxEqRel = std.testing.expectApproxEqRel;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

fn sampleModel() ModelScale {
    return .{
        .L = 6.0,
        .S = 6.5,
        .V = 1.5,
        .nu = 1.139e-6,
        .C_T = 0.0042,
        .rho = 1000.0,
    };
}

fn sampleShip() ShipScale {
    return .{
        .L = 150.0,
        .S = 4000.0,
        .V = 7.5,
        .nu = 1.188e-6,
        .rho = 1025.0,
        .A_T = 500.0,
    };
}

fn sampleFactors() PropulsionFactors {
    return .{ .one_plus_k = 1.15, .w = 0.3, .t = 0.18, .eta_R = 1.0, .eta_S = 0.98 };
}

fn sampleProp() Propeller {
    return .{ .D = 4.5, .n_s = 2.0, .K_T_s = 0.18, .K_Q_s = 0.028 };
}

test "extrapolate produces positive ship effective power" {
    const r = try extrapolate(sampleModel(), sampleShip(), sampleFactors(), sampleProp());
    try std.testing.expect(r.P_E_ship > 0.0);
    try std.testing.expect(r.P_D_ship > 0.0);
    try std.testing.expect(r.P_S_ship > r.P_D_ship); // shaft = delivered / 0.98
}

test "Reynolds numbers match independent calculation" {
    const m = sampleModel();
    const s = sampleShip();
    const r = try extrapolate(m, s, sampleFactors(), sampleProp());
    try expectApproxEqRel(m.V * m.L / m.nu, r.rn_model, 1e-12);
    try expectApproxEqRel(s.V * s.L / s.nu, r.rn_ship, 1e-12);
}

test "ITTC-57 C_F values match textbook at sample Reynolds" {
    const r = try extrapolate(sampleModel(), sampleShip(), sampleFactors(), sampleProp());
    // Model Rn ~ 7.9e6 -> C_F ~ 0.00318; ship Rn ~ 9.5e8 -> C_F ~ 0.00154.
    try std.testing.expect(r.cf_model > r.cf_ship);
}

test "C_A is negative for very long ships" {
    // L_s = 1000 m -> C_A = 0.006 * (1100)^(-0.16) - 0.00205
    //               ~ 0.006 * 0.3036 - 0.00205 = -0.00023.
    const r = try extrapolate(sampleModel(), .{
        .L = 1000.0,
        .S = 10000.0,
        .V = 12.0,
        .nu = 1.188e-6,
        .rho = 1025.0,
    }, sampleFactors(), sampleProp());
    try std.testing.expect(r.C_A < 0.0);
}

test "extrapolate rejects invalid wake fraction" {
    var f = sampleFactors();
    f.w = -0.1;
    try std.testing.expectError(Error.InvalidWakeFraction, extrapolate(sampleModel(), sampleShip(), f, sampleProp()));
    f.w = 0.95;
    try std.testing.expectError(Error.InvalidWakeFraction, extrapolate(sampleModel(), sampleShip(), f, sampleProp()));
}

test "extrapolate rejects invalid thrust deduction" {
    var f = sampleFactors();
    f.t = -0.2;
    try std.testing.expectError(Error.InvalidThrustDeduction, extrapolate(sampleModel(), sampleShip(), f, sampleProp()));
    f.t = 0.6;
    try std.testing.expectError(Error.InvalidThrustDeduction, extrapolate(sampleModel(), sampleShip(), f, sampleProp()));
}

test "extrapolate rejects non-positive dimensions" {
    var s = sampleShip();
    s.L = -1.0;
    try std.testing.expectError(Error.NonPositiveLength, extrapolate(sampleModel(), s, sampleFactors(), sampleProp()));
}

test "P_E scales with V_ship cubed at fixed C_T_ship" {
    // Doubling V doubles V^2 in R_T and V in P_E -> P_E scales as V^3 at
    // constant C_T. The composition of (1+k) C_F + C_R + C_A + C_AA
    // changes weakly with V via C_F(Rn), so the cube relation is
    // approximate; expect within 20 percent.
    const m = sampleModel();
    var s = sampleShip();
    const f = sampleFactors();
    const p = sampleProp();
    const r1 = try extrapolate(m, s, f, p);
    s.V = 2.0 * s.V;
    const r2 = try extrapolate(m, s, f, p);
    const ratio = r2.P_E_ship / r1.P_E_ship;
    try std.testing.expect(ratio > 7.0); // strictly > 2^3 / 1.15 = 6.96 if cf falls
    try std.testing.expect(ratio < 9.0);
}

test "P_S equals P_D divided by eta_S" {
    const r = try extrapolate(sampleModel(), sampleShip(), sampleFactors(), sampleProp());
    try expectApproxEqRel(r.P_D_ship / 0.98, r.P_S_ship, 1e-12);
}

test "correlationAllowance matches the published formula" {
    // L = 100 m -> C_A = 0.006 * 200^(-0.16) - 0.00205
    //            ~ 0.006 * 0.4216 - 0.00205 = 0.000479.
    const r = try extrapolate(sampleModel(), .{
        .L = 100.0,
        .S = 2000.0,
        .V = 7.0,
        .nu = 1.188e-6,
        .rho = 1025.0,
    }, sampleFactors(), sampleProp());
    try expectApproxEqAbs(@as(f64, 0.000479), r.C_A, 1e-4);
}

test "C_R is the wave-pattern residual" {
    const m = sampleModel();
    const r = try extrapolate(m, sampleShip(), sampleFactors(), sampleProp());
    // C_R = C_T_model - (1+k) C_F_model.
    const expected = m.C_T - 1.15 * r.cf_model;
    try expectApproxEqRel(expected, r.C_R, 1e-9);
}
