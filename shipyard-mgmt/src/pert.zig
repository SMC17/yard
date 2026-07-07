const std = @import("std");

pub const Error = error{
    InvalidTripleOrdering,
    NonPositiveDuration,
    UnequalLength,
};

/// PERT three-point estimate triple.
pub const Triple = struct {
    a_days: f64, // optimistic
    m_days: f64, // most likely
    b_days: f64, // pessimistic
};

/// Mean of the beta-PERT distribution:
///   mu = (a + 4 m + b) / 6.
pub fn mean(t: Triple) Error!f64 {
    if (!(t.a_days > 0)) return Error.NonPositiveDuration;
    if (!(t.m_days > 0)) return Error.NonPositiveDuration;
    if (!(t.b_days > 0)) return Error.NonPositiveDuration;
    if (!(t.a_days <= t.m_days and t.m_days <= t.b_days)) return Error.InvalidTripleOrdering;
    return (t.a_days + 4.0 * t.m_days + t.b_days) / 6.0;
}

/// Standard deviation of the beta-PERT distribution:
///   sigma = (b - a) / 6.
pub fn standardDeviation(t: Triple) Error!f64 {
    if (!(t.a_days <= t.m_days and t.m_days <= t.b_days)) return Error.InvalidTripleOrdering;
    return (t.b_days - t.a_days) / 6.0;
}

/// Variance.
pub fn variance(t: Triple) Error!f64 {
    const s = try standardDeviation(t);
    return s * s;
}

/// Project completion-time mean: sum of critical-path means.
pub fn projectMean(criticals: []const Triple) Error!f64 {
    var sum: f64 = 0.0;
    for (criticals) |t| sum += try mean(t);
    return sum;
}

/// Project variance: sum of critical-path variances.
pub fn projectVariance(criticals: []const Triple) Error!f64 {
    var sum: f64 = 0.0;
    for (criticals) |t| sum += try variance(t);
    return sum;
}

/// Z-score for a target finish T against project mean / variance:
///   z = (T - mu) / sigma.
pub fn zScore(T_days: f64, mu_days: f64, sigma_days: f64) Error!f64 {
    if (!(sigma_days > 0)) return Error.NonPositiveDuration;
    return (T_days - mu_days) / sigma_days;
}

test "mean at a=2, m=4, b=12 = (2 + 16 + 12) / 6 = 5" {
    const mu = try mean(.{ .a_days = 2.0, .m_days = 4.0, .b_days = 12.0 });
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), mu, 1e-9);
}

test "mean equals m when a = m = b" {
    const mu = try mean(.{ .a_days = 5.0, .m_days = 5.0, .b_days = 5.0 });
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), mu, 1e-12);
}

test "sigma at a=2, b=14 = 2" {
    const s = try standardDeviation(.{ .a_days = 2.0, .m_days = 8.0, .b_days = 14.0 });
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), s, 1e-9);
}

test "sigma = 0 when a = b" {
    const s = try standardDeviation(.{ .a_days = 5.0, .m_days = 5.0, .b_days = 5.0 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), s, 1e-12);
}

test "variance = sigma^2" {
    const t: Triple = .{ .a_days = 2.0, .m_days = 8.0, .b_days = 14.0 };
    const s = try standardDeviation(t);
    const v = try variance(t);
    try std.testing.expectApproxEqAbs(s * s, v, 1e-12);
}

test "project mean = sum of critical means" {
    const c = [_]Triple{
        .{ .a_days = 2.0, .m_days = 4.0, .b_days = 12.0 },
        .{ .a_days = 1.0, .m_days = 3.0, .b_days = 5.0 },
    };
    const mu = try projectMean(&c);
    const expected = try mean(c[0]) + try mean(c[1]);
    try std.testing.expectApproxEqAbs(expected, mu, 1e-9);
}

test "project variance = sum of critical variances" {
    const c = [_]Triple{
        .{ .a_days = 2.0, .m_days = 4.0, .b_days = 14.0 },
        .{ .a_days = 1.0, .m_days = 3.0, .b_days = 7.0 },
    };
    const v = try projectVariance(&c);
    const expected = try variance(c[0]) + try variance(c[1]);
    try std.testing.expectApproxEqAbs(expected, v, 1e-9);
}

test "Z-score: T at mean is 0" {
    const z = try zScore(10.0, 10.0, 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), z, 1e-12);
}

test "Z-score: T = mu + 2 sigma is +2" {
    const z = try zScore(14.0, 10.0, 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), z, 1e-12);
}

test "Z-score scales linearly with deviation" {
    const z = try zScore(11.0, 10.0, 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), z, 1e-12);
}

test "input rejection: invalid triple ordering (a > m)" {
    try std.testing.expectError(
        Error.InvalidTripleOrdering,
        mean(.{ .a_days = 5.0, .m_days = 3.0, .b_days = 10.0 }),
    );
}

test "input rejection: m > b" {
    try std.testing.expectError(
        Error.InvalidTripleOrdering,
        mean(.{ .a_days = 1.0, .m_days = 10.0, .b_days = 5.0 }),
    );
}

test "input rejection: zero sigma in Z-score" {
    try std.testing.expectError(Error.NonPositiveDuration, zScore(10.0, 10.0, 0.0));
}
