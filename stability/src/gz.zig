// GZ righting-arm computation: small-angle and wall-sided Atwood.
// Free-surface correction.
//
// Small angle:
//   GZ(phi) = GM * sin(phi)
//
// Wall-sided Atwood (valid until deck-edge immersion or bilge-emergence):
//   GZ(phi) = (GM + 0.5 * BM_T * tan(phi)^2) * sin(phi)
//
// Free-surface correction (per rectangular tank):
//   GG' = (rho_fluid / rho_seawater) * i_FS / V
//   i_FS = (1/12) * l * b^3
//
// Multiple tanks accumulate linearly:
//   GG'_total = sum_k (rho_k / rho_seawater) * i_FS_k / V
//
// Effective GM after free-surface correction:
//   GM_corrected = GM - GG'_total

const std = @import("std");

pub fn smallAngleGZ(GM: f64, phi_rad: f64) f64 {
    return GM * @sin(phi_rad);
}

pub fn wallSidedGZ(GM: f64, BM_T: f64, phi_rad: f64) f64 {
    const tan_phi = @tan(phi_rad);
    return (GM + 0.5 * BM_T * tan_phi * tan_phi) * @sin(phi_rad);
}

/// Rectangular-tank free-surface moment-of-inertia: i_FS = (1/12) * l * b^3.
pub fn rectTankIfs(l_m: f64, b_m: f64) f64 {
    return l_m * b_m * b_m * b_m / 12.0;
}

/// Single-tank free-surface correction contribution to GG'.
pub fn fsContribution(rho_fluid: f64, rho_seawater: f64, i_fs: f64, V_disp: f64) f64 {
    return (rho_fluid / rho_seawater) * i_fs / V_disp;
}

/// Effective GM after summing free-surface contributions from a list of tanks.
pub const Tank = struct {
    rho_fluid: f64,
    i_fs: f64,
};

pub fn effectiveGM(GM: f64, tanks: []const Tank, rho_seawater: f64, V_disp: f64) f64 {
    var ggprime: f64 = 0.0;
    for (tanks) |t| {
        ggprime += fsContribution(t.rho_fluid, rho_seawater, t.i_fs, V_disp);
    }
    return GM - ggprime;
}

const expectApproxEqAbs = std.testing.expectApproxEqAbs;
const expectApproxEqRel = std.testing.expectApproxEqRel;

test "smallAngleGZ is zero at zero heel" {
    try expectApproxEqAbs(@as(f64, 0.0), smallAngleGZ(0.5, 0.0), 1e-15);
}

test "smallAngleGZ equals GM at 90 degrees" {
    const half_pi = std.math.pi / 2.0;
    try expectApproxEqAbs(@as(f64, 0.5), smallAngleGZ(0.5, half_pi), 1e-15);
}

test "wallSided exceeds smallAngle at moderate phi (positive BM)" {
    const GM: f64 = 0.6389;
    const BM_T: f64 = 0.8889;
    const phi = 10.0 * std.math.pi / 180.0;
    const small = smallAngleGZ(GM, phi);
    const wall = wallSidedGZ(GM, BM_T, phi);
    try std.testing.expect(wall > small);
}

test "wallSidedGZ matches validation_fixtures box-barge values at 10 degrees" {
    // Box-barge L=10, B=4, T=1.5, KG=1.0:
    //   GM = 0.6389, BM_T = 0.8889
    // tan(10 deg) = 0.17633; tan^2 = 0.03110
    // (0.6389 + 0.5 * 0.8889 * 0.03110) * sin(10 deg)
    //  = (0.6389 + 0.01382) * 0.17365 = 0.1134 m approximately
    const GM: f64 = 0.6389;
    const BM_T: f64 = 0.8889;
    const phi = 10.0 * std.math.pi / 180.0;
    const wall = wallSidedGZ(GM, BM_T, phi);
    try expectApproxEqAbs(@as(f64, 0.1134), wall, 1e-3);
}

test "rectTankIfs equals l b^3 / 12" {
    try expectApproxEqAbs(@as(f64, 5.0 * 27.0 / 12.0), rectTankIfs(5.0, 3.0), 1e-12);
}

test "fsContribution matches validation_fixtures box-barge example" {
    // Tank 5 x 3 m, fresh water, sea water density 1025, V_disp = 60.
    // i_FS = 5 * 27 / 12 = 11.25
    // GG' = (1000 / 1025) * 11.25 / 60 = 0.1829 m (approximately 0.183 per codex).
    const ggp = fsContribution(1000.0, 1025.0, 11.25, 60.0);
    try expectApproxEqRel(@as(f64, 0.1829), ggp, 1e-3);
}

test "effectiveGM sums multiple tanks" {
    const tanks = [_]Tank{
        .{ .rho_fluid = 1000.0, .i_fs = 11.25 },
        .{ .rho_fluid = 1000.0, .i_fs = 5.0 },
    };
    const gm_eff = effectiveGM(0.6389, &tanks, 1025.0, 60.0);
    // GG'_total = (1000/1025) * (11.25 + 5.0) / 60 = 0.264 m
    // gm_eff = 0.6389 - 0.264 = 0.375
    try expectApproxEqAbs(@as(f64, 0.375), gm_eff, 1e-3);
}

test "smallAngleGZ matches wallSidedGZ at tiny phi" {
    const GM: f64 = 0.5;
    const BM_T: f64 = 1.0;
    const phi = 0.001;
    const small = smallAngleGZ(GM, phi);
    const wall = wallSidedGZ(GM, BM_T, phi);
    // At tiny phi, tan^2 ~ phi^2 << 1 so the correction term vanishes.
    try expectApproxEqRel(small, wall, 1e-5);
}
