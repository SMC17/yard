const std = @import("std");

pub const Error = error{
    NonPositiveWeight,
    NonPositiveBlockCount,
    NonPositiveLength,
    InvalidDistribution,
};

/// Average per-block reaction for a uniform block plan:
///   R_avg = W / N.
pub fn averagePerBlockN(W_n: f64, N: usize) Error!f64 {
    if (!(W_n > 0)) return Error.NonPositiveWeight;
    if (N == 0) return Error.NonPositiveBlockCount;
    const N_f: f64 = @floatFromInt(N);
    return W_n / N_f;
}

/// Per-block reaction for a non-uniform weight distribution
/// approximated as a trapezoidal load on a continuous beam:
///   R_i = w_i * dx
/// where w_i [N/m] is the longitudinal weight density at block i
/// and dx is the block spacing. Caller supplies the density at
/// each block.
pub fn nonUniformReactionsN(
    densities_n_per_m: []const f64,
    block_spacing_m: f64,
    R_out: []f64,
) Error!void {
    if (densities_n_per_m.len == 0) return Error.NonPositiveBlockCount;
    if (R_out.len != densities_n_per_m.len) return Error.InvalidDistribution;
    if (!(block_spacing_m > 0)) return Error.NonPositiveLength;
    for (densities_n_per_m, 0..) |w, i| {
        if (!(w >= 0)) return Error.InvalidDistribution;
        R_out[i] = w * block_spacing_m;
    }
}

/// Peak per-block reaction = max(R_i).
pub fn peakReactionN(R: []const f64) Error!f64 {
    if (R.len == 0) return Error.NonPositiveBlockCount;
    var peak: f64 = R[0];
    for (R[1..]) |r| if (r > peak) {
        peak = r;
    };
    return peak;
}

/// Sum of all block reactions; must equal the ship weight.
pub fn totalReactionN(R: []const f64) Error!f64 {
    if (R.len == 0) return Error.NonPositiveBlockCount;
    var sum: f64 = 0.0;
    for (R) |r| sum += r;
    return sum;
}

test "average per block: 50 MN weight, 100 blocks = 500 kN each" {
    const r = try averagePerBlockN(50.0e6, 100);
    try std.testing.expectApproxEqAbs(@as(f64, 500_000.0), r, 1e-6);
}

test "average per block scales linearly with W" {
    const r1 = try averagePerBlockN(50.0e6, 100);
    const r2 = try averagePerBlockN(100.0e6, 100);
    try std.testing.expectApproxEqAbs(2.0 * r1, r2, 1e-6);
}

test "average per block scales inversely with N" {
    const r1 = try averagePerBlockN(50.0e6, 100);
    const r2 = try averagePerBlockN(50.0e6, 200);
    try std.testing.expectApproxEqAbs(0.5 * r1, r2, 1e-6);
}

test "non-uniform reactions on a constant load" {
    const densities = [_]f64{ 1000.0, 1000.0, 1000.0, 1000.0 };
    var R: [4]f64 = undefined;
    try nonUniformReactionsN(&densities, 0.5, &R);
    inline for (0..4) |i| {
        try std.testing.expectApproxEqAbs(@as(f64, 500.0), R[i], 1e-12);
    }
}

test "non-uniform: linearly increasing load mirrors a wedge" {
    const densities = [_]f64{ 0.0, 1000.0, 2000.0, 3000.0 };
    var R: [4]f64 = undefined;
    try nonUniformReactionsN(&densities, 1.0, &R);
    inline for (0..4) |i| {
        const i_f: f64 = @floatFromInt(i);
        try std.testing.expectApproxEqAbs(i_f * 1000.0, R[i], 1e-12);
    }
}

test "peak reaction finds maximum" {
    const R = [_]f64{ 100.0, 250.0, 175.0, 300.0, 200.0 };
    const peak = try peakReactionN(&R);
    try std.testing.expectApproxEqAbs(@as(f64, 300.0), peak, 1e-12);
}

test "total reaction sums all elements" {
    const R = [_]f64{ 100.0, 200.0, 300.0, 400.0 };
    const total = try totalReactionN(&R);
    try std.testing.expectApproxEqAbs(@as(f64, 1000.0), total, 1e-12);
}

test "total reaction equals weight for uniform distribution" {
    const densities = [_]f64{ 5000.0, 5000.0, 5000.0, 5000.0 };
    var R: [4]f64 = undefined;
    try nonUniformReactionsN(&densities, 0.5, &R);
    const total = try totalReactionN(&R);
    try std.testing.expectApproxEqAbs(@as(f64, 10_000.0), total, 1e-9);
}

test "input rejection: zero W" {
    try std.testing.expectError(Error.NonPositiveWeight, averagePerBlockN(0.0, 100));
}

test "input rejection: zero blocks" {
    try std.testing.expectError(Error.NonPositiveBlockCount, averagePerBlockN(50.0e6, 0));
}

test "input rejection: zero block spacing" {
    const d = [_]f64{1000.0};
    var R: [1]f64 = undefined;
    try std.testing.expectError(Error.NonPositiveLength, nonUniformReactionsN(&d, 0.0, &R));
}

test "input rejection: negative density" {
    const d = [_]f64{ 1000.0, -500.0 };
    var R: [2]f64 = undefined;
    try std.testing.expectError(Error.InvalidDistribution, nonUniformReactionsN(&d, 0.5, &R));
}
