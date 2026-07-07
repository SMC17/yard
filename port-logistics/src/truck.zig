const std = @import("std");

pub const Error = error{
    NonPositiveRate,
    NonPositiveServers,
    NoSteadyState,
    InvalidHour,
};

/// Erlang-C approximation: probability that an arriving truck has
/// to wait at an M/M/c gate:
///   C(c, a) = (a^c / c!) / ((1 - rho) sum_{k=0}^{c-1} a^k/k! + a^c/c!)
/// where a = lambda / mu and rho = a / c. Returns the wait probability.
pub fn erlangC(lambda_per_hr: f64, mu_per_hr: f64, c_servers: u32) Error!f64 {
    if (!(lambda_per_hr > 0)) return Error.NonPositiveRate;
    if (!(mu_per_hr > 0)) return Error.NonPositiveRate;
    if (c_servers == 0) return Error.NonPositiveServers;
    const c_f: f64 = @floatFromInt(c_servers);
    const a = lambda_per_hr / mu_per_hr;
    const rho = a / c_f;
    if (!(rho < 1.0)) return Error.NoSteadyState;
    // a^c / c!
    var top: f64 = 1.0;
    var i: u32 = 1;
    while (i <= c_servers) : (i += 1) {
        const i_f: f64 = @floatFromInt(i);
        top = top * a / i_f;
    }
    // sum_{k=0}^{c-1} a^k / k!
    var sum: f64 = 0.0;
    var term: f64 = 1.0;
    sum += term;
    var k: u32 = 1;
    while (k < c_servers) : (k += 1) {
        const k_f: f64 = @floatFromInt(k);
        term = term * a / k_f;
        sum += term;
    }
    return top / ((1.0 - rho) * sum + top);
}

/// Erlang-C average waiting time in queue:
///   W_q = C(c, a) / (c mu - lambda).
pub fn averageWaitHr(
    lambda_per_hr: f64,
    mu_per_hr: f64,
    c_servers: u32,
) Error!f64 {
    const C = try erlangC(lambda_per_hr, mu_per_hr, c_servers);
    const c_f: f64 = @floatFromInt(c_servers);
    return C / (c_f * mu_per_hr - lambda_per_hr);
}

/// Average queue length:
///   L_q = lambda * W_q.
pub fn averageQueueLength(
    lambda_per_hr: f64,
    mu_per_hr: f64,
    c_servers: u32,
) Error!f64 {
    const W = try averageWaitHr(lambda_per_hr, mu_per_hr, c_servers);
    return lambda_per_hr * W;
}

/// Time-of-day demand multiplier from a single-peak triangle
/// centred at `peak_hour` (0-23) with daily total = average rate
/// times 24 hr:
///   factor(h) = max(0, 1 - |h - peak_hour| / half_width)
/// normalised so factor at peak = 2 and overnight = 0.
pub fn timeOfDayMultiplier(hour: u8, peak_hour: u8, half_width_hr: f64) Error!f64 {
    if (hour > 23) return Error.InvalidHour;
    if (peak_hour > 23) return Error.InvalidHour;
    if (!(half_width_hr > 0)) return Error.NoSteadyState;
    const h: f64 = @floatFromInt(hour);
    const p: f64 = @floatFromInt(peak_hour);
    const d = @abs(h - p);
    if (d >= half_width_hr) return 0.0;
    return 2.0 * (1.0 - d / half_width_hr);
}

test "Erlang-C at rho = 0 returns ~ 0 (no queue if no arrivals)" {
    const C = try erlangC(0.01, 100.0, 4);
    try std.testing.expect(C < 0.01);
}

test "Erlang-C rejects unstable rho >= 1" {
    try std.testing.expectError(
        Error.NoSteadyState,
        erlangC(120.0, 30.0, 4),
    );
}

test "Erlang-C in (0, 1)" {
    const C = try erlangC(100.0, 30.0, 4);
    try std.testing.expect(C > 0 and C < 1.0);
}

test "Erlang-C grows with utilisation" {
    const C_low = try erlangC(60.0, 30.0, 4); // rho = 0.5
    const C_high = try erlangC(108.0, 30.0, 4); // rho = 0.9
    try std.testing.expect(C_high > C_low);
}

test "average wait at lambda=80, mu=30, c=4: positive and finite" {
    const W = try averageWaitHr(80.0, 30.0, 4);
    try std.testing.expect(W > 0);
    try std.testing.expect(std.math.isFinite(W));
}

test "average wait increases when utilisation rises" {
    const W_low = try averageWaitHr(60.0, 30.0, 4);
    const W_high = try averageWaitHr(108.0, 30.0, 4);
    try std.testing.expect(W_high > W_low);
}

test "average queue length: L_q = lambda W_q" {
    const W = try averageWaitHr(80.0, 30.0, 4);
    const L = try averageQueueLength(80.0, 30.0, 4);
    try std.testing.expectApproxEqAbs(80.0 * W, L, 1e-9);
}

test "time-of-day at peak hour = 2.0" {
    const f = try timeOfDayMultiplier(12, 12, 6.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), f, 1e-12);
}

test "time-of-day at peak +/- half width is zero" {
    const f1 = try timeOfDayMultiplier(6, 12, 6.0);
    const f2 = try timeOfDayMultiplier(18, 12, 6.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), f1, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), f2, 1e-12);
}

test "time-of-day at half-distance gives factor = 1" {
    const f = try timeOfDayMultiplier(9, 12, 6.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), f, 1e-12);
}

test "time-of-day at midnight far from peak is zero" {
    const f = try timeOfDayMultiplier(0, 14, 4.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), f, 1e-12);
}

test "input rejection: hour > 23" {
    try std.testing.expectError(Error.InvalidHour, timeOfDayMultiplier(25, 12, 6.0));
}

test "input rejection: zero servers" {
    try std.testing.expectError(Error.NonPositiveServers, erlangC(100.0, 30.0, 0));
}

test "input rejection: zero mu" {
    try std.testing.expectError(Error.NonPositiveRate, erlangC(100.0, 0.0, 4));
}
