const std = @import("std");

pub const Error = error{
    UnequalLength,
    NonPositiveCycles,
    InsufficientPoints,
};

/// Palmgren-Miner linear cumulative damage:
///   D = sum_i n_i / N_i
/// where n_i is the applied cycles in stress block i and N_i is the
/// permissible cycles to failure (e.g. from `sn.cyclesToFailure`).
pub fn cumulativeDamage(n_applied: []const f64, N_permissible: []const f64) Error!f64 {
    if (n_applied.len != N_permissible.len) return Error.UnequalLength;
    if (n_applied.len == 0) return Error.InsufficientPoints;
    var D: f64 = 0.0;
    var i: usize = 0;
    while (i < n_applied.len) : (i += 1) {
        if (!(N_permissible[i] > 0)) return Error.NonPositiveCycles;
        D += n_applied[i] / N_permissible[i];
    }
    return D;
}

/// Verdict for a Miner sum against the unit-damage criterion.
pub const Verdict = enum {
    /// D < 1: design life satisfies the criterion.
    pass,
    /// D >= 1: cumulative damage exceeds unit; redesign required.
    fail,
};

pub fn verdict(D: f64) Verdict {
    if (D < 1.0) return .pass;
    return .fail;
}

/// Fraction of design life consumed if `n_applied` represents one
/// fraction of life: returns D directly (alias for clarity).
pub fn damageFraction(D: f64) f64 {
    return D;
}

/// Remaining life in cycles assuming the existing applied loading
/// repeats linearly: t_remain = (1 - D) / D times the existing applied
/// total cycles. Returns zero if D >= 1.
pub fn remainingLifeFromCurrentBlock(D_current: f64, n_total_current: f64) f64 {
    if (D_current <= 0.0) return std.math.inf(f64);
    if (D_current >= 1.0) return 0.0;
    return (1.0 - D_current) / D_current * n_total_current;
}

test "single-block cumulative damage" {
    const n = [_]f64{1e6};
    const N = [_]f64{1e7};
    const D = try cumulativeDamage(&n, &N);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), D, 1e-15);
    try std.testing.expectEqual(Verdict.pass, verdict(D));
}

test "two-block damage sum" {
    const n = [_]f64{ 1e6, 2e5 };
    const N = [_]f64{ 1e7, 5e5 };
    const D = try cumulativeDamage(&n, &N);
    // 0.1 + 0.4 = 0.5.
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), D, 1e-15);
    try std.testing.expectEqual(Verdict.pass, verdict(D));
}

test "damage exceeding unity fails" {
    const n = [_]f64{ 5e6, 5e6 };
    const N = [_]f64{ 1e7, 5e6 };
    const D = try cumulativeDamage(&n, &N);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), D, 1e-15);
    try std.testing.expectEqual(Verdict.fail, verdict(D));
}

test "damage exactly unity is fail (>= 1.0)" {
    const n = [_]f64{1.0};
    const N = [_]f64{1.0};
    const D = try cumulativeDamage(&n, &N);
    try std.testing.expectEqual(Verdict.fail, verdict(D));
}

test "remainingLifeFromCurrentBlock D=0.5 doubles current cycles" {
    const t_r = remainingLifeFromCurrentBlock(0.5, 1e6);
    try std.testing.expectApproxEqAbs(@as(f64, 1e6), t_r, 1e-6);
}

test "remainingLifeFromCurrentBlock D=0 is infinite" {
    const t_r = remainingLifeFromCurrentBlock(0.0, 1e6);
    try std.testing.expect(std.math.isInf(t_r));
}

test "remainingLifeFromCurrentBlock D=1 is zero" {
    const t_r = remainingLifeFromCurrentBlock(1.0, 1e6);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), t_r, 1e-15);
}

test "unequal-length inputs rejected" {
    const n = [_]f64{ 1, 2, 3 };
    const N = [_]f64{ 10, 20 };
    try std.testing.expectError(Error.UnequalLength, cumulativeDamage(&n, &N));
}

test "non-positive permissible cycles rejected" {
    const n = [_]f64{ 1, 2 };
    const N = [_]f64{ 10, 0 };
    try std.testing.expectError(Error.NonPositiveCycles, cumulativeDamage(&n, &N));
}

test "empty input rejected" {
    const n: []const f64 = &[_]f64{};
    const N: []const f64 = &[_]f64{};
    try std.testing.expectError(Error.InsufficientPoints, cumulativeDamage(n, N));
}
