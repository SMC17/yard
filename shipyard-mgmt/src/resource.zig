const std = @import("std");

pub const Error = error{
    InvalidWindow,
    UnequalLength,
    NonPositiveResource,
    BufferTooSmall,
};

/// Resource-loading window for a single activity:
///   start_day .. start_day + duration_days, with constant rate
///   `rate_per_day`.
pub const ResourceWindow = struct {
    start_day: usize,
    duration_days: usize,
    rate_per_day: f64,
};

/// Histogram of total resource usage per day. The output buffer
/// `hist` is of length `horizon_days`; each cell accumulates the
/// resource rate of every active activity on that day.
pub fn buildHistogram(
    activities: []const ResourceWindow,
    horizon_days: usize,
    hist: []f64,
) Error!void {
    if (horizon_days == 0) return Error.InvalidWindow;
    if (hist.len < horizon_days) return Error.BufferTooSmall;
    for (hist[0..horizon_days]) |*c| c.* = 0.0;
    for (activities) |a| {
        if (!(a.rate_per_day >= 0)) return Error.NonPositiveResource;
        const end = a.start_day + a.duration_days;
        if (end > horizon_days) return Error.InvalidWindow;
        var d: usize = a.start_day;
        while (d < end) : (d += 1) {
            hist[d] += a.rate_per_day;
        }
    }
}

/// Peak load across the histogram.
pub fn peakLoad(hist: []const f64) Error!f64 {
    if (hist.len == 0) return Error.InvalidWindow;
    var peak: f64 = hist[0];
    for (hist[1..]) |v| if (v > peak) {
        peak = v;
    };
    return peak;
}

/// Average load.
pub fn averageLoad(hist: []const f64) Error!f64 {
    if (hist.len == 0) return Error.InvalidWindow;
    var sum: f64 = 0.0;
    for (hist) |v| sum += v;
    const N_f: f64 = @floatFromInt(hist.len);
    return sum / N_f;
}

/// Total resource-days = sum of histogram.
pub fn totalResourceDays(hist: []const f64) Error!f64 {
    if (hist.len == 0) return Error.InvalidWindow;
    var sum: f64 = 0.0;
    for (hist) |v| sum += v;
    return sum;
}

/// Smoothness ratio: average / peak. Higher means more even
/// loading. A ratio of 1 means uniform; values around 0.5-0.7 are
/// realistic for shipyard schedules.
pub fn smoothnessRatio(hist: []const f64) Error!f64 {
    const peak = try peakLoad(hist);
    const avg = try averageLoad(hist);
    if (!(peak > 0)) return 1.0;
    return avg / peak;
}

test "single activity 5-day window at 10 men/day" {
    const acts = [_]ResourceWindow{
        .{ .start_day = 0, .duration_days = 5, .rate_per_day = 10.0 },
    };
    var hist: [10]f64 = undefined;
    try buildHistogram(&acts, 10, &hist);
    inline for (0..5) |i| {
        try std.testing.expectApproxEqAbs(@as(f64, 10.0), hist[i], 1e-12);
    }
    inline for (5..10) |i| {
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), hist[i], 1e-12);
    }
}

test "two overlapping activities" {
    const acts = [_]ResourceWindow{
        .{ .start_day = 0, .duration_days = 5, .rate_per_day = 10.0 },
        .{ .start_day = 2, .duration_days = 5, .rate_per_day = 8.0 },
    };
    var hist: [10]f64 = undefined;
    try buildHistogram(&acts, 10, &hist);
    // Days 0-1: only A (10). Days 2-4: A+B (18). Days 5-6: only B (8). Days 7+: 0.
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), hist[1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 18.0), hist[3], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), hist[6], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), hist[8], 1e-12);
}

test "peak load: 18 at day 3 in overlap case" {
    const acts = [_]ResourceWindow{
        .{ .start_day = 0, .duration_days = 5, .rate_per_day = 10.0 },
        .{ .start_day = 2, .duration_days = 5, .rate_per_day = 8.0 },
    };
    var hist: [10]f64 = undefined;
    try buildHistogram(&acts, 10, &hist);
    const peak = try peakLoad(&hist);
    try std.testing.expectApproxEqAbs(@as(f64, 18.0), peak, 1e-12);
}

test "average load over 10-day horizon: 2*10 + 3*18 + 2*8 + 3*0 = 90 / 10 = 9" {
    const acts = [_]ResourceWindow{
        .{ .start_day = 0, .duration_days = 5, .rate_per_day = 10.0 },
        .{ .start_day = 2, .duration_days = 5, .rate_per_day = 8.0 },
    };
    var hist: [10]f64 = undefined;
    try buildHistogram(&acts, 10, &hist);
    const avg = try averageLoad(&hist);
    try std.testing.expectApproxEqAbs(@as(f64, 9.0), avg, 1e-12);
}

test "total resource-days: sum of all rate-days" {
    const acts = [_]ResourceWindow{
        .{ .start_day = 0, .duration_days = 5, .rate_per_day = 10.0 },
        .{ .start_day = 2, .duration_days = 5, .rate_per_day = 8.0 },
    };
    var hist: [10]f64 = undefined;
    try buildHistogram(&acts, 10, &hist);
    const total = try totalResourceDays(&hist);
    // 5 * 10 + 5 * 8 = 50 + 40 = 90.
    try std.testing.expectApproxEqAbs(@as(f64, 90.0), total, 1e-12);
}

test "smoothness ratio: average / peak" {
    const acts = [_]ResourceWindow{
        .{ .start_day = 0, .duration_days = 5, .rate_per_day = 10.0 },
        .{ .start_day = 2, .duration_days = 5, .rate_per_day = 8.0 },
    };
    var hist: [10]f64 = undefined;
    try buildHistogram(&acts, 10, &hist);
    const sr = try smoothnessRatio(&hist);
    try std.testing.expectApproxEqAbs(@as(f64, 9.0 / 18.0), sr, 1e-12);
}

test "smoothness ratio for uniform load is 1.0" {
    const acts = [_]ResourceWindow{
        .{ .start_day = 0, .duration_days = 10, .rate_per_day = 5.0 },
    };
    var hist: [10]f64 = undefined;
    try buildHistogram(&acts, 10, &hist);
    const sr = try smoothnessRatio(&hist);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), sr, 1e-12);
}

test "empty histogram returns 1.0 smoothness (no peak)" {
    var hist: [10]f64 = [_]f64{0.0} ** 10;
    const sr = try smoothnessRatio(&hist);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), sr, 1e-12);
}

test "input rejection: activity extends past horizon" {
    const acts = [_]ResourceWindow{
        .{ .start_day = 8, .duration_days = 5, .rate_per_day = 10.0 },
    };
    var hist: [10]f64 = undefined;
    try std.testing.expectError(Error.InvalidWindow, buildHistogram(&acts, 10, &hist));
}

test "input rejection: zero horizon" {
    var hist: [0]f64 = undefined;
    const acts: []const ResourceWindow = &[_]ResourceWindow{};
    try std.testing.expectError(Error.InvalidWindow, buildHistogram(acts, 0, &hist));
}

test "input rejection: negative rate" {
    const acts = [_]ResourceWindow{
        .{ .start_day = 0, .duration_days = 5, .rate_per_day = -1.0 },
    };
    var hist: [10]f64 = undefined;
    try std.testing.expectError(Error.NonPositiveResource, buildHistogram(&acts, 10, &hist));
}
