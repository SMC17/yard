const std = @import("std");

pub const Error = error{
    NonPositiveDisplacement,
    NonPositiveDistance,
    InvalidGeometry,
};

/// Buoyancy as the stern enters the water at position x measured
/// from the way-end (positive forward). Approximated as
///   B(x) = rho g A_W(x) * d_imm(x)
/// for an immersed wedge of waterplane area A_W and depth d_imm.
/// The kernel exposes a simple linear-with-immersion estimator;
/// callers with a real hull-form model should compose externally.
pub fn buoyancyAtImmersionN(
    rho_kg_per_m3: f64,
    g_mps2: f64,
    A_W_m2: f64,
    d_imm_m: f64,
) Error!f64 {
    if (!(rho_kg_per_m3 > 0)) return Error.NonPositiveDisplacement;
    if (!(A_W_m2 > 0)) return Error.NonPositiveDistance;
    if (!(d_imm_m >= 0)) return Error.NonPositiveDistance;
    return rho_kg_per_m3 * g_mps2 * A_W_m2 * d_imm_m;
}

/// Stern lift-off occurs when buoyancy at the stern exceeds the
/// remaining weight on the after cradle (the rest is supported by
/// the forward cradle). Lift-off check:
///   B(x_pivot) >= W * (L_cg - L_aft_cradle) / (L_fore_cradle - L_aft_cradle)
/// Returns true if the buoyancy at the given position is sufficient.
pub fn sternLiftedOff(
    B_n: f64,
    W_n: f64,
    L_cg_m: f64,
    L_aft_cradle_m: f64,
    L_fore_cradle_m: f64,
) Error!bool {
    if (!(W_n > 0)) return Error.NonPositiveDisplacement;
    if (!(L_fore_cradle_m > L_aft_cradle_m)) return Error.InvalidGeometry;
    const fraction = (L_cg_m - L_aft_cradle_m) /
        (L_fore_cradle_m - L_aft_cradle_m);
    if (!(fraction >= 0.0 and fraction <= 1.0)) return Error.InvalidGeometry;
    return B_n >= W_n * fraction;
}

/// Forward-cradle reaction force as the stern starts to lift off:
///   R_fwd = W (L_cg - L_aft_cradle) / (L_fore_cradle - L_aft_cradle)
///        + (drop in buoyancy contribution).
/// At the pivot point R_fwd is at its peak.
pub fn forwardCradleReactionN(
    W_n: f64,
    L_cg_m: f64,
    L_aft_cradle_m: f64,
    L_fore_cradle_m: f64,
) Error!f64 {
    if (!(W_n > 0)) return Error.NonPositiveDisplacement;
    if (!(L_fore_cradle_m > L_aft_cradle_m)) return Error.InvalidGeometry;
    const arm = L_cg_m - L_aft_cradle_m;
    const span = L_fore_cradle_m - L_aft_cradle_m;
    return W_n * arm / span;
}

test "buoyancy linear in immersion depth" {
    const B1 = try buoyancyAtImmersionN(1025.0, 9.81, 500.0, 0.5);
    const B2 = try buoyancyAtImmersionN(1025.0, 9.81, 500.0, 1.0);
    try std.testing.expectApproxEqAbs(2.0 * B1, B2, 1e-6);
}

test "buoyancy at d_imm = 0 is zero" {
    const B = try buoyancyAtImmersionN(1025.0, 9.81, 500.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), B, 1e-12);
}

test "stern lift-off when B exceeds required fraction" {
    // W = 100, L_cg = 50, L_aft = 30, L_fwd = 80.
    // fraction = 20 / 50 = 0.4. Required B = 40.
    const v_below = try sternLiftedOff(30.0, 100.0, 50.0, 30.0, 80.0);
    const v_above = try sternLiftedOff(50.0, 100.0, 50.0, 30.0, 80.0);
    try std.testing.expectEqual(false, v_below);
    try std.testing.expectEqual(true, v_above);
}

test "stern lift-off exactly at required B returns true" {
    const v = try sternLiftedOff(40.0, 100.0, 50.0, 30.0, 80.0);
    try std.testing.expectEqual(true, v);
}

test "forward cradle reaction at CG mid-span = W/2" {
    // L_cg = 55 = (30 + 80) / 2. fraction = 25/50 = 0.5. R = 50.
    const R = try forwardCradleReactionN(100.0, 55.0, 30.0, 80.0);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), R, 1e-12);
}

test "forward cradle reaction at CG over fore cradle = W" {
    const R = try forwardCradleReactionN(100.0, 80.0, 30.0, 80.0);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), R, 1e-12);
}

test "forward cradle reaction at CG over aft cradle = 0" {
    const R = try forwardCradleReactionN(100.0, 30.0, 30.0, 80.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), R, 1e-12);
}

test "forward cradle reaction scales linearly with W" {
    const R1 = try forwardCradleReactionN(100.0, 55.0, 30.0, 80.0);
    const R2 = try forwardCradleReactionN(200.0, 55.0, 30.0, 80.0);
    try std.testing.expectApproxEqAbs(2.0 * R1, R2, 1e-9);
}

test "input rejection: degenerate cradle span" {
    try std.testing.expectError(
        Error.InvalidGeometry,
        forwardCradleReactionN(100.0, 50.0, 80.0, 30.0),
    );
}

test "input rejection: CG outside cradle span" {
    try std.testing.expectError(
        Error.InvalidGeometry,
        sternLiftedOff(40.0, 100.0, 90.0, 30.0, 80.0),
    );
}
