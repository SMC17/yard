// Froude number and Froude-scaling utilities.

const std = @import("std");

pub const Error = error{
    NonPositiveLength,
    NonPositiveGravity,
};

/// Froude number Fn = V / sqrt(g L).
pub fn number(v: f64, l: f64, g: f64) f64 {
    return v / @sqrt(g * l);
}

/// Speed for a target Froude number.
pub fn speedForFn(fn_val: f64, l: f64, g: f64) Error!f64 {
    if (l <= 0.0) return Error.NonPositiveLength;
    if (g <= 0.0) return Error.NonPositiveGravity;
    return fn_val * @sqrt(g * l);
}

/// Wave resistance coefficient C_R is treated as Froude-dependent and
/// Reynolds-independent in the ITTC-78 extrapolation (copied model → ship).
pub fn residualCopiesUnderFroude(c_r_model: f64) f64 {
    return c_r_model;
}

const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "Fn invariant under Froude scaling" {
    const g: f64 = 9.80665;
    const l_m: f64 = 5.0;
    const l_s: f64 = 100.0;
    const lambda = l_m / l_s;
    const v_m: f64 = 1.5;
    const v_s = v_m / @sqrt(lambda);
    const fn_m = number(v_m, l_m, g);
    const fn_s = number(v_s, l_s, g);
    try expectApproxEqAbs(fn_m, fn_s, 1e-12);
}