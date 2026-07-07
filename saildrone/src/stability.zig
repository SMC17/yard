const std = @import("std");

pub const Error = error{
    NonPositiveGM,
    NonPositiveBM,
    InvalidAngle,
};

/// Wall-sided GZ approximation:
///   GZ(phi) = (GM + 0.5 BM_T tan^2 phi) sin phi.
/// Valid for small-to-moderate angles (typically up to deck-edge
/// immersion).
pub fn gzWallSidedM(GM_m: f64, BM_T_m: f64, phi_rad: f64) Error!f64 {
    if (!(GM_m > 0)) return Error.NonPositiveGM;
    if (!(BM_T_m > 0)) return Error.NonPositiveBM;
    if (!(phi_rad >= 0 and phi_rad < std.math.pi / 2.0)) return Error.InvalidAngle;
    return (GM_m + 0.5 * BM_T_m * std.math.tan(phi_rad) * std.math.tan(phi_rad)) *
        @sin(phi_rad);
}

/// Find the heel angle that maximises GZ over the wall-sided region
/// (numerically; 1-degree increments up to `phi_max_deg`).
/// The wall-sided approximation diverges at large heel; caller
/// should pass phi_max_deg consistent with the deck-edge angle.
pub fn phiMaxGZRadInRange(GM_m: f64, BM_T_m: f64, phi_max_deg: u8) Error!f64 {
    if (!(GM_m > 0)) return Error.NonPositiveGM;
    if (!(BM_T_m > 0)) return Error.NonPositiveBM;
    if (phi_max_deg == 0 or phi_max_deg >= 90) return Error.InvalidAngle;
    var best_phi: f64 = 0.0;
    var best_gz: f64 = 0.0;
    const deg = std.math.pi / 180.0;
    var i: usize = 1;
    while (i <= phi_max_deg) : (i += 1) {
        const phi = @as(f64, @floatFromInt(i)) * deg;
        const gz = gzWallSidedM(GM_m, BM_T_m, phi) catch continue;
        if (gz > best_gz) {
            best_gz = gz;
            best_phi = phi;
        }
    }
    return best_phi;
}

/// Search to the typical USV deck-edge / downflooding angle of
/// 30 deg.
pub fn phiMaxGZRad(GM_m: f64, BM_T_m: f64) Error!f64 {
    return try phiMaxGZRadInRange(GM_m, BM_T_m, 30);
}

/// Maximum GZ over the search range.
pub fn maxGZM(GM_m: f64, BM_T_m: f64) Error!f64 {
    const phi = try phiMaxGZRad(GM_m, BM_T_m);
    return try gzWallSidedM(GM_m, BM_T_m, phi);
}

pub const Verdict = enum {
    /// Both GZ_max >= GZ_min and GM >= GM_min.
    pass,
    fail,
};

/// USV intact stability verdict (IMO USV Code draft):
///   GZ_max >= 0.20 m  AND  GM >= 0.15 m.
pub fn imoUsvDraftVerdict(GM_m: f64, BM_T_m: f64) Error!Verdict {
    if (GM_m < 0.15) return .fail;
    const gz_max = try maxGZM(GM_m, BM_T_m);
    if (gz_max < 0.20) return .fail;
    return .pass;
}

test "GZ at phi = 0 is zero" {
    const gz = try gzWallSidedM(0.5, 2.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), gz, 1e-12);
}

test "GZ at phi = 30 deg, GM = 0.5, BM_T = 2: closed form" {
    const phi = std.math.pi / 6.0;
    const gz = try gzWallSidedM(0.5, 2.0, phi);
    const t = std.math.tan(@as(f64, std.math.pi / 6.0));
    const expected = (0.5 + 0.5 * 2.0 * t * t) * @sin(@as(f64, std.math.pi / 6.0));
    try std.testing.expectApproxEqAbs(expected, gz, 1e-9);
}

test "GZ scales with sin phi at small angles" {
    const gz_small = try gzWallSidedM(0.5, 2.0, 0.05);
    // At small phi: GZ ~ GM * sin phi.
    try std.testing.expectApproxEqAbs(0.5 * @sin(@as(f64, 0.05)), gz_small, 1e-3);
}

test "GZ_max is at deck-edge angle for wall-sided regime" {
    const phi_max = try phiMaxGZRad(0.5, 2.0);
    const deg = 180.0 / std.math.pi;
    try std.testing.expect(phi_max * deg >= 1.0);
    try std.testing.expect(phi_max * deg <= 30.0);
}

test "max GZ at typical USV: GM = 0.30, BM_T = 1.5 within deck-edge band" {
    const gz = try maxGZM(0.30, 1.5);
    try std.testing.expect(gz > 0.1);
    // Wall-sided diverges at large heel; the 30-deg search ceiling
    // bounds it within a realistic operational envelope.
    try std.testing.expect(gz < 1.5);
}

test "verdict pass when GM and GZ_max both meet thresholds" {
    // High GM, high BM_T -> both thresholds met.
    const v = try imoUsvDraftVerdict(0.40, 2.5);
    try std.testing.expectEqual(Verdict.pass, v);
}

test "verdict fail when GM below 0.15" {
    const v = try imoUsvDraftVerdict(0.10, 2.5);
    try std.testing.expectEqual(Verdict.fail, v);
}

test "verdict fail when GZ_max below 0.20" {
    // Low GM and low BM_T -> GZ_max < 0.2 over the 30-deg search.
    // GM=0.16, BM_T=0.05: max GZ ~ 0.16 * sin(30) = 0.08 (linear branch
    // dominates); well below 0.20.
    const v = try imoUsvDraftVerdict(0.16, 0.05);
    try std.testing.expectEqual(Verdict.fail, v);
}

test "input rejection: zero GM" {
    try std.testing.expectError(Error.NonPositiveGM, gzWallSidedM(0.0, 2.0, 0.3));
}

test "input rejection: phi >= pi/2" {
    try std.testing.expectError(Error.InvalidAngle, gzWallSidedM(0.5, 2.0, 2.0));
}
