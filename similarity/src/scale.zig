// Geometric, kinematic, and dynamic similarity transformations.
//
// λ = L_model / L_ship (model scale ratio; λ < 1 for typical tank models).
// Geometric: all linear dimensions scale by λ between model and ship.
// Kinematic (Froude): V_ship = V_model / sqrt(λ) at equal Fn.
// Dynamic (Reynolds): Rn scales as V*L/nu; cannot match Fn and Rn simultaneously
// at the same fluid — ITTC-78 treats wave residual as Fn-scaled and viscous
// via separate C_F evaluation at each scale.

const std = @import("std");
const froude = @import("froude.zig");
const reynolds = @import("reynolds.zig");

pub const Error = error{
    NonPositiveLambda,
    NonPositiveLength,
    NonPositiveSpeed,
    NonPositiveViscosity,
};

/// Scale ratio λ = L_model / L_ship.
pub const ScaleRatio = struct {
    lambda: f64,

    pub fn fromLengths(l_model: f64, l_ship: f64) Error!ScaleRatio {
        if (l_model <= 0.0 or l_ship <= 0.0) return Error.NonPositiveLength;
        return .{ .lambda = l_model / l_ship };
    }

    pub fn shipFromModelLinear(self: ScaleRatio, x_model: f64) Error!f64 {
        if (self.lambda <= 0.0) return Error.NonPositiveLambda;
        return x_model / self.lambda;
    }

    pub fn modelFromShipLinear(self: ScaleRatio, x_ship: f64) Error!f64 {
        if (self.lambda <= 0.0) return Error.NonPositiveLambda;
        return x_ship * self.lambda;
    }

    pub fn shipFromModelArea(self: ScaleRatio, a_model: f64) Error!f64 {
        if (self.lambda <= 0.0) return Error.NonPositiveLambda;
        const inv = 1.0 / self.lambda;
        return a_model * inv * inv;
    }

    pub fn shipFromModelVolume(self: ScaleRatio, v_model: f64) Error!f64 {
        if (self.lambda <= 0.0) return Error.NonPositiveLambda;
        const inv = 1.0 / self.lambda;
        return v_model * inv * inv * inv;
    }

    /// Froude kinematic scaling: V_ship from model test speed.
    pub fn shipSpeedFromModel(self: ScaleRatio, v_model: f64, g: f64) Error!f64 {
        if (self.lambda <= 0.0) return Error.NonPositiveLambda;
        if (v_model < 0.0) return Error.NonPositiveSpeed;
        _ = g;
        const inv_sqrt = 1.0 / @sqrt(self.lambda);
        return v_model * inv_sqrt;
    }

    /// Inverse: model tank speed for target ship speed at equal Fn.
    pub fn modelSpeedFromShip(self: ScaleRatio, v_ship: f64, g: f64) Error!f64 {
        if (self.lambda <= 0.0) return Error.NonPositiveLambda;
        if (v_ship < 0.0) return Error.NonPositiveSpeed;
        _ = g;
        return v_ship * @sqrt(self.lambda);
    }
};

/// Result of checking the three similarity rules at a scale pair.
pub const ThreeRulesReport = struct {
    geometric_ok: bool,
    kinematic_ok: bool,
    dynamic_ok: bool,
    lambda: f64,
    fn_model: f64,
    fn_ship: f64,
    rn_model: f64,
    rn_ship: f64,
    /// Reynolds ratio Rn_ship / Rn_model at Froude-matched speeds (same ν).
    reynolds_ratio: f64,

    pub fn allGeometricKinematic(self: ThreeRulesReport) bool {
        return self.geometric_ok and self.kinematic_ok;
    }
};

/// Evaluate geometric + kinematic (Froude) + dynamic (Reynolds) consistency.
pub fn evaluateThreeRules(
    l_model: f64,
    l_ship: f64,
    v_model: f64,
    v_ship: f64,
    nu: f64,
    g: f64,
    tol_fn: f64,
    tol_rn_ratio: f64,
) Error!ThreeRulesReport {
    const sr = try ScaleRatio.fromLengths(l_model, l_ship);
    const v_ship_froude = try sr.shipSpeedFromModel(v_model, g);
    const fn_m = froude.number(v_model, l_model, g);
    const fn_s = froude.number(v_ship, l_ship, g);
    const rn_m = reynolds.number(v_model, l_model, nu);
    const rn_s = reynolds.number(v_ship, l_ship, nu);
    const rn_ratio = if (rn_m > 0.0) rn_s / rn_m else 0.0;
    const expected_rn_ratio = 1.0 / (sr.lambda * @sqrt(sr.lambda));

    return .{
        .geometric_ok = sr.lambda > 0.0 and sr.lambda < 1.0,
        .kinematic_ok = @abs(fn_m - fn_s) <= tol_fn and @abs(v_ship - v_ship_froude) <= tol_fn * v_ship_froude,
        .dynamic_ok = @abs(rn_ratio - expected_rn_ratio) <= tol_rn_ratio * expected_rn_ratio,
        .lambda = sr.lambda,
        .fn_model = fn_m,
        .fn_ship = fn_s,
        .rn_model = rn_m,
        .rn_ship = rn_s,
        .reynolds_ratio = rn_ratio,
    };
}

const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "volume scales as lambda^-3" {
    const sr = try ScaleRatio.fromLengths(5.0, 100.0);
    const v_ship = try sr.shipFromModelVolume(10.0);
    try expectApproxEqAbs(@as(f64, 80000.0), v_ship, 1e-6);
}

test "Froude speed scaling 5m model to 100m ship" {
    const sr = try ScaleRatio.fromLengths(5.0, 100.0);
    const v_ship = try sr.shipSpeedFromModel(1.5, 9.80665);
    // λ = 0.05, V_ship = 1.5 / sqrt(0.05) ≈ 6.708
    try expectApproxEqAbs(@as(f64, 6.708), v_ship, 0.01);
}

test "three rules: Froude matched, Reynolds cannot match at same nu" {
    const report = try evaluateThreeRules(5.0, 100.0, 1.5, 6.708, 1.188e-6, 9.80665, 0.01, 0.05);
    try std.testing.expect(report.geometric_ok);
    try std.testing.expect(report.kinematic_ok);
    // Rn ratio should be λ^(-3/2) ≈ 89.4 at Froude-matched speeds
    try expectApproxEqAbs(@as(f64, 89.44), report.reynolds_ratio, 1.0);
}