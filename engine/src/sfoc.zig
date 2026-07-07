const std = @import("std");

pub const Error = error{
    InvalidLoadFraction,
    NonPositiveSfoc,
    DegenerateData,
};

/// Three-point SFOC quadratic fit. Inputs are (x_50, x_75, x_100) =
/// (50, 75, 100) % MCR and (y_50, y_75, y_100) the corresponding
/// SFOC values in g / kWh. Returns the quadratic coefficients
/// (a, b, c) such that SFOC(x) = a + b * x + c * x^2.
pub fn fitThreePoint(y_50: f64, y_75: f64, y_100: f64) Error!struct { a: f64, b: f64, c: f64 } {
    if (!(y_50 > 0)) return Error.NonPositiveSfoc;
    if (!(y_75 > 0)) return Error.NonPositiveSfoc;
    if (!(y_100 > 0)) return Error.NonPositiveSfoc;
    // Solve the 3x3 system on x in {50, 75, 100}.
    //   a +  50 b + 2500 c  = y_50
    //   a +  75 b + 5625 c  = y_75
    //   a + 100 b + 10000 c = y_100
    // Subtract first from second and third:
    //   25 b + 3125 c = y_75 - y_50
    //   50 b + 7500 c = y_100 - y_50
    // Multiply first by 2: 50 b + 6250 c = 2 (y_75 - y_50).
    // Subtract: (7500 - 6250) c = (y_100 - y_50) - 2 (y_75 - y_50)
    //           1250 c = y_100 - 2 y_75 + y_50.
    const c = (y_100 - 2.0 * y_75 + y_50) / 1250.0;
    const b = (y_75 - y_50 - 3125.0 * c) / 25.0;
    const a = y_50 - 50.0 * b - 2500.0 * c;
    return .{ .a = a, .b = b, .c = c };
}

/// Evaluate the SFOC quadratic at a given % MCR `x` in [0, 110].
pub fn evaluateSfoc(coeffs: anytype, x_pct_mcr: f64) Error!f64 {
    if (!(x_pct_mcr >= 0.0 and x_pct_mcr <= 110.0)) return Error.InvalidLoadFraction;
    return coeffs.a + coeffs.b * x_pct_mcr + coeffs.c * x_pct_mcr * x_pct_mcr;
}

/// Engine power at percentage MCR:
///   P_kw = (x_pct_mcr / 100) * P_MCR_kw.
pub fn engineLoadKw(x_pct_mcr: f64, P_MCR_kw: f64) Error!f64 {
    if (!(x_pct_mcr >= 0.0 and x_pct_mcr <= 110.0)) return Error.InvalidLoadFraction;
    if (!(P_MCR_kw > 0)) return Error.NonPositiveSfoc;
    return x_pct_mcr * 0.01 * P_MCR_kw;
}

/// Fuel mass flow rate [kg / h]:
///   m_dot = SFOC [g/kWh] * P [kW] / 1000.
pub fn fuelMassFlowKgPerHr(sfoc_g_per_kwh: f64, P_kw: f64) Error!f64 {
    if (!(sfoc_g_per_kwh > 0)) return Error.NonPositiveSfoc;
    if (!(P_kw >= 0)) return Error.NonPositiveSfoc;
    return sfoc_g_per_kwh * P_kw * 1.0e-3;
}

test "three-point fit reproduces the three input values exactly" {
    const c = try fitThreePoint(180.0, 175.0, 180.0);
    const v50 = try evaluateSfoc(c, 50.0);
    const v75 = try evaluateSfoc(c, 75.0);
    const v100 = try evaluateSfoc(c, 100.0);
    try std.testing.expectApproxEqAbs(@as(f64, 180.0), v50, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 175.0), v75, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 180.0), v100, 1e-9);
}

test "fit produces a parabolic minimum between the endpoints" {
    // y_50 = y_100 = 180, y_75 = 170 -> minimum at x = 75.
    const c = try fitThreePoint(180.0, 170.0, 180.0);
    const v75 = try evaluateSfoc(c, 75.0);
    const v60 = try evaluateSfoc(c, 60.0);
    const v90 = try evaluateSfoc(c, 90.0);
    try std.testing.expect(v75 < v60);
    try std.testing.expect(v75 < v90);
}

test "linear case: y_50 = 180, y_75 = 178, y_100 = 176" {
    const c = try fitThreePoint(180.0, 178.0, 176.0);
    // c coefficient should be (176 - 2*178 + 180) / 1250 = 0.
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), c.c, 1e-12);
}

test "engine load: 75 % MCR of 20 000 kW MCR = 15 000 kW" {
    const P = try engineLoadKw(75.0, 20_000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 15_000.0), P, 1e-9);
}

test "fuel mass flow at 170 g/kWh and 15 MW = 2550 kg/h" {
    const mdot = try fuelMassFlowKgPerHr(170.0, 15_000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2550.0), mdot, 1e-9);
}

test "input rejection: load outside [0, 110]" {
    const c = try fitThreePoint(180.0, 175.0, 180.0);
    try std.testing.expectError(Error.InvalidLoadFraction, evaluateSfoc(c, -1.0));
    try std.testing.expectError(Error.InvalidLoadFraction, evaluateSfoc(c, 115.0));
}

test "input rejection: non-positive SFOC" {
    try std.testing.expectError(Error.NonPositiveSfoc, fitThreePoint(0.0, 175.0, 180.0));
}

test "input rejection: zero MCR" {
    try std.testing.expectError(Error.NonPositiveSfoc, engineLoadKw(75.0, 0.0));
}
