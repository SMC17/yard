const std = @import("std");

pub const Error = error{
    NonPositiveHeight,
    NonPositiveDepth,
    NonPositiveDensity,
    InvalidSlope,
    NonPositiveStability,
};

/// Wave-transmission coefficient K_t = H_t / H_i for a rubble-mound
/// breakwater per Goda & Ahrens 1982 empirical fit:
///   K_t = 0.5 (1 - tanh((F + 0.6 d) / B))
/// approximation; for free-board F > 0 in still water.
/// Caller supplies F (free-board), d (depth at structure toe), B
/// (crest width). All in m.
pub fn transmissionCoefficient(F_m: f64, d_m: f64, B_m: f64) Error!f64 {
    if (!(d_m > 0)) return Error.NonPositiveDepth;
    if (!(B_m > 0)) return Error.NonPositiveHeight;
    return 0.5 * (1.0 - std.math.tanh((F_m + 0.6 * d_m) / B_m));
}

/// Hudson formula 1959 for armour-stone median weight W_50 [kg]:
///   W_50 = rho_s g H^3 / (K_D (rho_s / rho_w - 1)^3 cot(alpha))
/// where K_D is the stability coefficient (typ. 2.0 for rough
/// natural stone, 8 for tribar), rho_s is the armour density, rho_w
/// is the seawater density, H is the design wave height, alpha is
/// the breakwater seaward slope.
pub fn hudsonMedianWeightKg(
    H_m: f64,
    rho_s_kg_per_m3: f64,
    rho_w_kg_per_m3: f64,
    K_D: f64,
    alpha_rad: f64,
) Error!f64 {
    if (!(H_m > 0)) return Error.NonPositiveHeight;
    if (!(rho_s_kg_per_m3 > rho_w_kg_per_m3)) return Error.NonPositiveDensity;
    if (!(K_D > 0)) return Error.NonPositiveStability;
    if (!(alpha_rad > 0 and alpha_rad < std.math.pi / 2.0)) return Error.InvalidSlope;
    const S = rho_s_kg_per_m3 / rho_w_kg_per_m3;
    const cot_alpha = @cos(alpha_rad) / @sin(alpha_rad);
    return rho_s_kg_per_m3 * 9.80665 * H_m * H_m * H_m /
        (K_D * (S - 1.0) * (S - 1.0) * (S - 1.0) * cot_alpha);
}

/// Run-up height R_u from a regular wave on a smooth slope per
/// Hunt 1959 surf-similarity formula:
///   R_u = xi * H    if xi < 2.3
///   R_u = 3.2 H     if xi >= 2.3
/// where xi = tan(alpha) / sqrt(H / L_0) is the Iribarren number.
pub fn iribarrenNumber(H_m: f64, L_0_m: f64, alpha_rad: f64) Error!f64 {
    if (!(H_m > 0)) return Error.NonPositiveHeight;
    if (!(L_0_m > 0)) return Error.NonPositiveDepth;
    if (!(alpha_rad > 0 and alpha_rad < std.math.pi / 2.0)) return Error.InvalidSlope;
    return @tan(alpha_rad) / @sqrt(H_m / L_0_m);
}

pub fn runupHeightHuntM(H_m: f64, L_0_m: f64, alpha_rad: f64) Error!f64 {
    const xi = try iribarrenNumber(H_m, L_0_m, alpha_rad);
    if (xi < 2.3) return xi * H_m;
    return 3.2 * H_m;
}

test "transmission coefficient: large free-board gives K_t -> 0" {
    const K_t = try transmissionCoefficient(10.0, 5.0, 5.0);
    try std.testing.expect(K_t < 0.1);
}

test "transmission coefficient: submerged (F < 0) gives K_t -> 0.5+" {
    const K_t = try transmissionCoefficient(-5.0, 5.0, 5.0);
    try std.testing.expect(K_t > 0.4);
}

test "transmission coefficient between 0 and 1" {
    const K_t = try transmissionCoefficient(0.0, 5.0, 5.0);
    try std.testing.expect(K_t >= 0.0 and K_t <= 1.0);
}

test "Hudson W_50 at H=4, rho_s=2650, rho_w=1025, K_D=2, slope 1:1.5" {
    // tan_alpha = 1/1.5, alpha = atan(0.6667) ~ 0.5880 rad.
    const alpha = std.math.atan(@as(f64, 1.0 / 1.5));
    const W = try hudsonMedianWeightKg(4.0, 2650.0, 1025.0, 2.0, alpha);
    // S = 2650/1025 = 2.585. (S-1) = 1.585. (S-1)^3 = 3.985.
    // cot(alpha) = 1.5.
    // W = 2650 * 9.80665 * 64 / (2 * 3.985 * 1.5) = 1 663 408 / 11.96 = 139 113 kg.
    const S = 2650.0 / 1025.0;
    const expected = 2650.0 * 9.80665 * 64.0 / (2.0 * std.math.pow(f64, S - 1.0, 3) * 1.5);
    try std.testing.expectApproxEqAbs(expected, W, 1.0);
}

test "Hudson W_50 scales with H^3" {
    const alpha = std.math.atan(@as(f64, 1.0 / 1.5));
    const W_2 = try hudsonMedianWeightKg(2.0, 2650.0, 1025.0, 2.0, alpha);
    const W_4 = try hudsonMedianWeightKg(4.0, 2650.0, 1025.0, 2.0, alpha);
    try std.testing.expectApproxEqAbs(8.0, W_4 / W_2, 1e-9);
}

test "Hudson W_50 inversely proportional to K_D" {
    const alpha = std.math.atan(@as(f64, 1.0 / 1.5));
    const W_2 = try hudsonMedianWeightKg(4.0, 2650.0, 1025.0, 2.0, alpha);
    const W_8 = try hudsonMedianWeightKg(4.0, 2650.0, 1025.0, 8.0, alpha);
    try std.testing.expectApproxEqAbs(0.25, W_8 / W_2, 1e-9);
}

test "Iribarren number at H=2, L_0=50, slope 1:2" {
    const alpha = std.math.atan(@as(f64, 0.5));
    const xi = try iribarrenNumber(2.0, 50.0, alpha);
    const expected = 0.5 / @sqrt(@as(f64, 2.0 / 50.0));
    try std.testing.expectApproxEqAbs(expected, xi, 1e-9);
}

test "run-up: surging regime xi >= 2.3 caps at 3.2 H" {
    const alpha = std.math.atan(@as(f64, 1.0));
    const R = try runupHeightHuntM(2.0, 50.0, alpha);
    try std.testing.expectApproxEqAbs(@as(f64, 3.2 * 2.0), R, 1e-9);
}

test "run-up: plunging regime xi < 2.3 is xi H" {
    const alpha = std.math.atan(@as(f64, 0.1));
    const xi = try iribarrenNumber(2.0, 50.0, alpha);
    const R = try runupHeightHuntM(2.0, 50.0, alpha);
    try std.testing.expectApproxEqAbs(xi * 2.0, R, 1e-9);
}

test "input rejection: zero crest width" {
    try std.testing.expectError(Error.NonPositiveHeight, transmissionCoefficient(0.5, 5.0, 0.0));
}

test "input rejection: rho_s <= rho_w" {
    const alpha = std.math.atan(@as(f64, 0.5));
    try std.testing.expectError(
        Error.NonPositiveDensity,
        hudsonMedianWeightKg(4.0, 1000.0, 1025.0, 2.0, alpha),
    );
}

test "input rejection: zero K_D" {
    const alpha = std.math.atan(@as(f64, 0.5));
    try std.testing.expectError(
        Error.NonPositiveStability,
        hudsonMedianWeightKg(4.0, 2650.0, 1025.0, 0.0, alpha),
    );
}

test "input rejection: slope >= pi/2" {
    try std.testing.expectError(
        Error.InvalidSlope,
        hudsonMedianWeightKg(4.0, 2650.0, 1025.0, 2.0, 2.0),
    );
}
