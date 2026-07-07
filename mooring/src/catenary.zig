const std = @import("std");

pub const Error = error{
    NonPositiveWeight,
    NonPositiveHorizontalForce,
    NonPositiveLength,
    NoConvergence,
};

/// Catenary parameter a = H / w. The catenary shape, with the lowest
/// point at the origin, is y(x) = a (cosh(x/a) - 1).
pub fn catenaryParameterM(H_n: f64, w_n_per_m: f64) Error!f64 {
    if (!(H_n > 0)) return Error.NonPositiveHorizontalForce;
    if (!(w_n_per_m > 0)) return Error.NonPositiveWeight;
    return H_n / w_n_per_m;
}

/// Catenary curve y(x) with low point at the origin.
pub fn catenaryY(a_m: f64, x_m: f64) f64 {
    return a_m * (std.math.cosh(x_m / a_m) - 1.0);
}

/// Tension magnitude at horizontal position x measured from the low
/// point: T(x) = H cosh(x/a) = w (a + y(x)).
pub fn tensionAtXN(H_n: f64, a_m: f64, x_m: f64) f64 {
    return H_n * std.math.cosh(x_m / a_m);
}

/// Arc length s(x) measured from the low point: s(x) = a sinh(x/a).
pub fn arcLengthM(a_m: f64, x_m: f64) f64 {
    return a_m * std.math.sinh(x_m / a_m);
}

/// Solve for the horizontal force H given a fairlead at horizontal
/// distance x from the low point and vertical height y above the low
/// point, weight per unit length w. Uses Newton iteration on
///   f(a) = a (cosh(x/a) - 1) - y = 0
/// then returns H = w a.
pub fn solveHorizontalForceFromXYN(
    x_m: f64,
    y_m: f64,
    w_n_per_m: f64,
) Error!f64 {
    if (!(w_n_per_m > 0)) return Error.NonPositiveWeight;
    if (!(x_m > 0)) return Error.NonPositiveLength;
    if (!(y_m > 0)) return Error.NonPositiveLength;
    // Bracket: f(a) = a (cosh(x/a) - 1) - y.
    // As a -> 0+, f -> +inf (cosh grows). As a -> +inf, f -> -y.
    // f is monotonic in a, so bisection on a wide bracket converges.
    var lo: f64 = 1e-9;
    var hi: f64 = 1.0;
    var f_hi: f64 = hi * (std.math.cosh(x_m / hi) - 1.0) - y_m;
    var grow_iter: usize = 0;
    while (f_hi > 0 and grow_iter < 200) : (grow_iter += 1) {
        lo = hi;
        hi *= 4.0;
        f_hi = hi * (std.math.cosh(x_m / hi) - 1.0) - y_m;
    }
    if (f_hi > 0) return Error.NoConvergence;
    var iter: usize = 0;
    while (iter < 200) : (iter += 1) {
        const mid = 0.5 * (lo + hi);
        const f_mid = mid * (std.math.cosh(x_m / mid) - 1.0) - y_m;
        if (f_mid > 0) {
            lo = mid;
        } else {
            hi = mid;
        }
        if ((hi - lo) / @max(hi, 1e-12) < 1e-12) {
            return w_n_per_m * 0.5 * (lo + hi);
        }
    }
    return Error.NoConvergence;
}

/// Vertical reaction at the fairlead measured from the low point:
/// V = w s = H sinh(x/a).
pub fn verticalForceN(H_n: f64, a_m: f64, x_m: f64) f64 {
    return H_n * std.math.sinh(x_m / a_m);
}

/// Tangent angle theta(x) at horizontal x from the low point:
/// tan(theta) = sinh(x/a). Returned in radians, range [0, pi/2).
pub fn tangentAngleRad(a_m: f64, x_m: f64) f64 {
    return std.math.atan(std.math.sinh(x_m / a_m));
}

test "catenary parameter a = H / w" {
    const a = try catenaryParameterM(1000.0, 50.0);
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), a, 1e-12);
}

test "catenary y(0) = 0 at the low point" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), catenaryY(20.0, 0.0), 1e-12);
}

test "catenary y at x = a equals a (cosh 1 - 1) ~ 0.5431 a" {
    const a: f64 = 20.0;
    const y = catenaryY(a, a);
    const expected = a * (std.math.cosh(@as(f64, 1.0)) - 1.0);
    try std.testing.expectApproxEqAbs(expected, y, 1e-12);
    try std.testing.expectApproxEqAbs(a * 0.5430806348, y, 1e-6);
}

test "tension at low point equals H" {
    try std.testing.expectApproxEqAbs(@as(f64, 1000.0), tensionAtXN(1000.0, 20.0, 0.0), 1e-12);
}

test "tension grows monotonically with horizontal distance" {
    const T0 = tensionAtXN(1000.0, 20.0, 0.0);
    const T1 = tensionAtXN(1000.0, 20.0, 10.0);
    const T2 = tensionAtXN(1000.0, 20.0, 20.0);
    try std.testing.expect(T0 < T1);
    try std.testing.expect(T1 < T2);
}

test "tension matches H + w y identity" {
    // T(x) = H cosh(x/a) = H + H (cosh - 1) = H + w * y(x).
    const H: f64 = 1000.0;
    const w: f64 = 50.0;
    const a = try catenaryParameterM(H, w);
    const x: f64 = 15.0;
    const T = tensionAtXN(H, a, x);
    const y = catenaryY(a, x);
    try std.testing.expectApproxEqAbs(H + w * y, T, 1e-9);
}

test "arc length s(0) = 0 at low point" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), arcLengthM(20.0, 0.0), 1e-12);
}

test "arc length s exceeds chord x for nonzero x" {
    const x: f64 = 10.0;
    const s = arcLengthM(20.0, x);
    try std.testing.expect(s > x);
}

test "solveHorizontalForceFromXYN reproduces forward catenary" {
    // Forward: H = 1000, w = 50, a = 20. At x = 15: y = 20 (cosh(0.75) - 1).
    const H_truth: f64 = 1000.0;
    const w: f64 = 50.0;
    const a = try catenaryParameterM(H_truth, w);
    const x: f64 = 15.0;
    const y = catenaryY(a, x);
    const H_solved = try solveHorizontalForceFromXYN(x, y, w);
    try std.testing.expectApproxEqAbs(H_truth, H_solved, 1e-6);
}

test "solveHorizontalForceFromXYN converges over typical H range" {
    // Range excludes the H >> w x regime where the catenary degenerates
    // to a straight rope and cosh(x/a) - 1 loses precision.
    const w: f64 = 100.0;
    const test_H = [_]f64{ 10.0, 1.0e2, 1.0e3, 1.0e4 };
    for (test_H) |H_truth| {
        const a = try catenaryParameterM(H_truth, w);
        const x: f64 = 25.0;
        const y = catenaryY(a, x);
        const H_solved = try solveHorizontalForceFromXYN(x, y, w);
        const rel_err = @abs(H_solved - H_truth) / H_truth;
        try std.testing.expect(rel_err < 1e-4);
    }
}

test "vertical force V = w * arc length" {
    const H: f64 = 1000.0;
    const w: f64 = 50.0;
    const a = try catenaryParameterM(H, w);
    const x: f64 = 12.0;
    const V = verticalForceN(H, a, x);
    const s = arcLengthM(a, x);
    try std.testing.expectApproxEqAbs(w * s, V, 1e-9);
}

test "tangent angle zero at low point" {
    const theta = tangentAngleRad(20.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), theta, 1e-12);
}

test "tangent angle pi/4 when sinh(x/a) = 1, i.e. x = a asinh(1)" {
    const a: f64 = 30.0;
    const x = a * std.math.asinh(@as(f64, 1.0));
    const theta = tangentAngleRad(a, x);
    try std.testing.expectApproxEqAbs(std.math.pi / 4.0, theta, 1e-12);
}

test "non-positive weight rejected" {
    try std.testing.expectError(Error.NonPositiveWeight, catenaryParameterM(1000.0, 0.0));
    try std.testing.expectError(Error.NonPositiveWeight, solveHorizontalForceFromXYN(10.0, 1.0, 0.0));
}

test "non-positive H rejected" {
    try std.testing.expectError(Error.NonPositiveHorizontalForce, catenaryParameterM(0.0, 50.0));
}

test "non-positive x or y rejected in inverse solve" {
    try std.testing.expectError(Error.NonPositiveLength, solveHorizontalForceFromXYN(0.0, 1.0, 50.0));
    try std.testing.expectError(Error.NonPositiveLength, solveHorizontalForceFromXYN(10.0, 0.0, 50.0));
}
