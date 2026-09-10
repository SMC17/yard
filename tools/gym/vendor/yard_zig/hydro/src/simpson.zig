// Composite Simpson quadrature on precomputed ordinate arrays.
//
// Naval architecture convention: integration is performed on tabulated
// station / waterline ordinates produced by an offsets table. This module
// consumes such arrays directly and is allocator-free.

const std = @import("std");

pub const Error = error{
    InvalidOrdinateCount,
    NonPositiveSpacing,
};

/// Composite Simpson's 1/3 rule.
/// Requires odd ordinate count (>= 3) and h > 0.
/// Returns the approximate integral over [x_0, x_0 + (n-1)*h].
pub fn simpson13(ordinates: []const f64, h: f64) Error!f64 {
    if (ordinates.len < 3 or ordinates.len % 2 == 0) return Error.InvalidOrdinateCount;
    if (!(h > 0.0)) return Error.NonPositiveSpacing;

    var sum: f64 = ordinates[0] + ordinates[ordinates.len - 1];
    var i: usize = 1;
    while (i < ordinates.len - 1) : (i += 1) {
        const coeff: f64 = if (i % 2 == 1) 4.0 else 2.0;
        sum += coeff * ordinates[i];
    }
    return sum * h / 3.0;
}

/// Composite Simpson's 3/8 rule.
/// Requires ordinate count of the form 3k+1 (>= 4) and h > 0.
pub fn simpson38(ordinates: []const f64, h: f64) Error!f64 {
    if (ordinates.len < 4 or (ordinates.len - 1) % 3 != 0) return Error.InvalidOrdinateCount;
    if (!(h > 0.0)) return Error.NonPositiveSpacing;

    var sum: f64 = ordinates[0] + ordinates[ordinates.len - 1];
    var i: usize = 1;
    while (i < ordinates.len - 1) : (i += 1) {
        const coeff: f64 = if (i % 3 == 0) 2.0 else 3.0;
        sum += coeff * ordinates[i];
    }
    return sum * 3.0 * h / 8.0;
}

test "simpson13 exact for cubic polynomial on five points" {
    // f(x) = x^3 on [0, 2]; exact integral = 4.0.
    // Simpson 1/3 is exact for polynomials of degree <= 3.
    const ordinates = [_]f64{ 0.0, 0.125, 1.0, 3.375, 8.0 }; // x = 0, 0.5, 1, 1.5, 2
    const h: f64 = 0.5;
    const result = try simpson13(&ordinates, h);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), result, 1e-12);
}

test "simpson13 exact for constant function" {
    const ordinates = [_]f64{ 1.0, 1.0, 1.0 };
    const h: f64 = 1.0;
    const result = try simpson13(&ordinates, h);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result, 1e-15);
}

test "simpson13 rejects even ordinate count" {
    const ordinates = [_]f64{ 0.0, 1.0, 4.0, 9.0 };
    try std.testing.expectError(Error.InvalidOrdinateCount, simpson13(&ordinates, 1.0));
}

test "simpson13 rejects non-positive spacing" {
    const ordinates = [_]f64{ 0.0, 1.0, 4.0 };
    try std.testing.expectError(Error.NonPositiveSpacing, simpson13(&ordinates, 0.0));
    try std.testing.expectError(Error.NonPositiveSpacing, simpson13(&ordinates, -1.0));
}

test "simpson38 exact for cubic polynomial on four points" {
    // f(x) = x^3 on [0, 3]; exact integral = 20.25.
    const ordinates = [_]f64{ 0.0, 1.0, 8.0, 27.0 };
    const h: f64 = 1.0;
    const result = try simpson38(&ordinates, h);
    try std.testing.expectApproxEqAbs(@as(f64, 20.25), result, 1e-12);
}

test "simpson38 rejects ordinate counts not of form 3k+1" {
    const ordinates5 = [_]f64{ 0.0, 1.0, 2.0, 3.0, 4.0 };
    try std.testing.expectError(Error.InvalidOrdinateCount, simpson38(&ordinates5, 1.0));
    const ordinates6 = [_]f64{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0 };
    try std.testing.expectError(Error.InvalidOrdinateCount, simpson38(&ordinates6, 1.0));
}
