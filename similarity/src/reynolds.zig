// Reynolds number and viscous scaling utilities.

const std = @import("std");

/// Reynolds number Rn = V L / nu.
pub fn number(v: f64, l: f64, nu: f64) f64 {
    return v * l / nu;
}

/// ITTC-57 friction is evaluated separately at model and ship Rn.
/// At Froude-matched speeds: V_s/V_m = 1/sqrt(λ), L_s/L_m = 1/λ, so
/// Rn_s/Rn_m = (V_s L_s)/(V_m L_m) = λ^(-3/2).
pub fn ratioAtFroudeMatch(lambda: f64) f64 {
    return 1.0 / (lambda * @sqrt(lambda));
}

const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "Reynolds ratio at Froude match" {
    const lambda: f64 = 0.05;
    const nu: f64 = 1.188e-6;
    const l_m: f64 = 5.0;
    const l_s: f64 = 100.0;
    const v_m: f64 = 1.5;
    const v_s = v_m / @sqrt(lambda);
    const rn_m = number(v_m, l_m, nu);
    const rn_s = number(v_s, l_s, nu);
    try expectApproxEqAbs(ratioAtFroudeMatch(lambda), rn_s / rn_m, 1e-9);
}