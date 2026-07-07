const std = @import("std");

pub const Error = error{
    NonPositiveRate,
    NonPositiveServers,
    InvalidUtilisation,
    NoSteadyState,
};

/// Server utilisation rho = lambda / (c mu) where lambda is the
/// arrival rate (trucks/hr), mu the service rate per server, c the
/// number of servers (gate lanes).
pub fn serverUtilisation(
    lambda_per_hr: f64,
    c_servers: u32,
    mu_per_hr_per_server: f64,
) Error!f64 {
    if (!(lambda_per_hr > 0)) return Error.NonPositiveRate;
    if (c_servers == 0) return Error.NonPositiveServers;
    if (!(mu_per_hr_per_server > 0)) return Error.NonPositiveRate;
    const c_f: f64 = @floatFromInt(c_servers);
    return lambda_per_hr / (c_f * mu_per_hr_per_server);
}

/// M/M/1 average wait time in the queue [hr]:
///   W_q = rho / (mu (1 - rho)).
pub fn mm1QueueWaitHr(lambda: f64, mu: f64) Error!f64 {
    if (!(lambda > 0)) return Error.NonPositiveRate;
    if (!(mu > 0)) return Error.NonPositiveRate;
    if (lambda >= mu) return Error.NoSteadyState;
    const rho = lambda / mu;
    return rho / (mu * (1.0 - rho));
}

/// M/M/1 average number in queue:
///   L_q = rho^2 / (1 - rho).
pub fn mm1QueueLength(lambda: f64, mu: f64) Error!f64 {
    if (!(lambda > 0)) return Error.NonPositiveRate;
    if (!(mu > 0)) return Error.NonPositiveRate;
    if (lambda >= mu) return Error.NoSteadyState;
    const rho = lambda / mu;
    return rho * rho / (1.0 - rho);
}

/// M/M/c approximate average wait time via Erlang-C. The kernel
/// returns the approximation
///   W_q ~ rho / (c mu (1 - rho))
/// which is exact for c = 1 and a useful approximation for c > 1
/// when used as an upper bound (worst case M/M/1 per lane).
pub fn mmcApproxQueueWaitHr(
    lambda_per_hr: f64,
    c_servers: u32,
    mu_per_hr_per_server: f64,
) Error!f64 {
    if (c_servers == 0) return Error.NonPositiveServers;
    const rho = try serverUtilisation(lambda_per_hr, c_servers, mu_per_hr_per_server);
    if (rho >= 1.0) return Error.NoSteadyState;
    const c_f: f64 = @floatFromInt(c_servers);
    return rho / (c_f * mu_per_hr_per_server * (1.0 - rho));
}

/// Throughput at given utilisation:
///   throughput = rho * c * mu  (trucks/hr).
pub fn throughputPerHr(rho: f64, c_servers: u32, mu_per_hr: f64) Error!f64 {
    if (!(rho > 0 and rho <= 1.0)) return Error.InvalidUtilisation;
    if (c_servers == 0) return Error.NonPositiveServers;
    const c_f: f64 = @floatFromInt(c_servers);
    return rho * c_f * mu_per_hr;
}

test "rho at 100 arrivals/h, 4 servers at 30/h = 100/(120) = 0.833" {
    const rho = try serverUtilisation(100.0, 4, 30.0);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0 / 120.0), rho, 1e-12);
}

test "rho at zero arrivals impossible -> error" {
    try std.testing.expectError(Error.NonPositiveRate, serverUtilisation(0.0, 4, 30.0));
}

test "M/M/1 wait at lambda=20, mu=30: rho = 2/3" {
    const W = try mm1QueueWaitHr(20.0, 30.0);
    const rho = 20.0 / 30.0;
    const expected = rho / (30.0 * (1.0 - rho));
    try std.testing.expectApproxEqAbs(expected, W, 1e-12);
}

test "M/M/1 wait blows up as lambda -> mu" {
    const W_safe = try mm1QueueWaitHr(20.0, 30.0);
    const W_close = try mm1QueueWaitHr(29.0, 30.0);
    try std.testing.expect(W_close > W_safe * 5.0);
}

test "M/M/1 rejects unstable system lambda >= mu" {
    try std.testing.expectError(Error.NoSteadyState, mm1QueueWaitHr(30.0, 30.0));
    try std.testing.expectError(Error.NoSteadyState, mm1QueueWaitHr(40.0, 30.0));
}

test "M/M/1 queue length closed form" {
    const L = try mm1QueueLength(20.0, 30.0);
    const rho = 2.0 / 3.0;
    try std.testing.expectApproxEqAbs(rho * rho / (1.0 - rho), L, 1e-12);
}

test "M/M/c approx wait at c=2, lambda=40, mu=30 per lane" {
    const W = try mmcApproxQueueWaitHr(40.0, 2, 30.0);
    try std.testing.expect(W > 0);
    try std.testing.expect(std.math.isFinite(W));
}

test "M/M/c approx rejects rho >= 1" {
    try std.testing.expectError(Error.NoSteadyState, mmcApproxQueueWaitHr(60.0, 2, 30.0));
}

test "throughput at rho=0.8, c=4, mu=30 = 96 trucks/h" {
    const T = try throughputPerHr(0.8, 4, 30.0);
    try std.testing.expectApproxEqAbs(@as(f64, 96.0), T, 1e-12);
}

test "throughput linear in rho" {
    const T_4 = try throughputPerHr(0.4, 4, 30.0);
    const T_8 = try throughputPerHr(0.8, 4, 30.0);
    try std.testing.expectApproxEqAbs(2.0 * T_4, T_8, 1e-12);
}

test "throughput linear in c" {
    const T_2 = try throughputPerHr(0.8, 2, 30.0);
    const T_4 = try throughputPerHr(0.8, 4, 30.0);
    try std.testing.expectApproxEqAbs(2.0 * T_2, T_4, 1e-12);
}

test "input rejection: rho > 1" {
    try std.testing.expectError(Error.InvalidUtilisation, throughputPerHr(1.5, 4, 30.0));
}

test "input rejection: zero servers" {
    try std.testing.expectError(Error.NonPositiveServers, throughputPerHr(0.5, 0, 30.0));
}

test "input rejection: zero mu" {
    try std.testing.expectError(Error.NonPositiveRate, serverUtilisation(100.0, 4, 0.0));
}
