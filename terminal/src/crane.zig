const std = @import("std");

pub const Error = error{
    NonPositiveRate,
    NonPositiveCount,
    InvalidLossFraction,
};

/// Ship-to-shore (STS) crane productivity in moves per hour.
/// Typical modern post-Panamax STS yields 25-35 mph single-cycle;
/// 30-45 with dual-cycling (mixing loading and unloading).
pub fn netMovesPerHour(
    cycle_time_sec: f64,
    dual_cycling_uplift: f64,
    loss_fraction: f64,
) Error!f64 {
    if (!(cycle_time_sec > 0)) return Error.NonPositiveRate;
    if (!(dual_cycling_uplift >= 1.0)) return Error.NonPositiveRate;
    if (!(loss_fraction >= 0.0 and loss_fraction < 1.0)) return Error.InvalidLossFraction;
    const single_cycle = 3600.0 / cycle_time_sec;
    return single_cycle * dual_cycling_uplift * (1.0 - loss_fraction);
}

/// Default loss fraction from operational delays (twistlock fumbling,
/// hatch covers, signaler delay, etc.). Typical 10-15 %.
pub const default_loss_fraction: f64 = 0.10;

/// Default dual-cycling uplift (Goodchild 2005 study found ~ 1.2-1.4
/// in practice).
pub const default_dual_cycling_uplift: f64 = 1.25;

/// Multi-crane productivity wedge: when n cranes work the same
/// vessel, interference reduces per-crane productivity:
///   eta(n) = 1 / (1 + (n - 1) * interference_factor)
/// with interference_factor ~ 0.10-0.15.
pub fn multiCraneEfficiency(n_cranes: u32, interference_factor: f64) Error!f64 {
    if (n_cranes == 0) return Error.NonPositiveCount;
    if (!(interference_factor >= 0)) return Error.InvalidLossFraction;
    const n_f: f64 = @floatFromInt(n_cranes - 1);
    return 1.0 / (1.0 + n_f * interference_factor);
}

/// Total vessel-moves rate for n cranes:
///   total = n * per_crane_rate * eta(n).
pub fn vesselMovesPerHr(
    n_cranes: u32,
    per_crane_mph: f64,
    interference_factor: f64,
) Error!f64 {
    if (!(per_crane_mph > 0)) return Error.NonPositiveRate;
    if (n_cranes == 0) return Error.NonPositiveCount;
    const eta = try multiCraneEfficiency(n_cranes, interference_factor);
    const n_f: f64 = @floatFromInt(n_cranes);
    return n_f * per_crane_mph * eta;
}

test "single-cycle: 90 sec cycle, no loss = 40 mph" {
    const r = try netMovesPerHour(90.0, 1.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 40.0), r, 1e-12);
}

test "dual-cycling 1.25 uplift on 90 sec cycle = 50 mph" {
    const r = try netMovesPerHour(90.0, 1.25, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), r, 1e-12);
}

test "loss fraction 0.10 reduces output by 10 %" {
    const r0 = try netMovesPerHour(90.0, 1.0, 0.0);
    const r1 = try netMovesPerHour(90.0, 1.0, 0.10);
    try std.testing.expectApproxEqAbs(0.9 * r0, r1, 1e-12);
}

test "default constants" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.10), default_loss_fraction, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.25), default_dual_cycling_uplift, 1e-12);
}

test "multi-crane efficiency at n=1 is 1.0" {
    const eta = try multiCraneEfficiency(1, 0.10);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), eta, 1e-12);
}

test "multi-crane efficiency at n=4, interference=0.10 = 1/1.3" {
    const eta = try multiCraneEfficiency(4, 0.10);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 1.3), eta, 1e-12);
}

test "multi-crane efficiency decreasing in n" {
    const e1 = try multiCraneEfficiency(1, 0.10);
    const e2 = try multiCraneEfficiency(2, 0.10);
    const e3 = try multiCraneEfficiency(3, 0.10);
    try std.testing.expect(e1 > e2);
    try std.testing.expect(e2 > e3);
}

test "multi-crane: zero interference gives unity efficiency" {
    const eta = try multiCraneEfficiency(10, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), eta, 1e-12);
}

test "vessel moves: 1 crane at 35 mph = 35" {
    const r = try vesselMovesPerHr(1, 35.0, 0.10);
    try std.testing.expectApproxEqAbs(@as(f64, 35.0), r, 1e-12);
}

test "vessel moves: 4 cranes at 35 mph, interference 0.10 = 4*35/1.3" {
    const r = try vesselMovesPerHr(4, 35.0, 0.10);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0 * 35.0 / 1.3), r, 1e-9);
}

test "vessel moves grow slower than linear in n cranes (interference)" {
    const r1 = try vesselMovesPerHr(1, 35.0, 0.10);
    const r4 = try vesselMovesPerHr(4, 35.0, 0.10);
    try std.testing.expect(r4 > r1);
    try std.testing.expect(r4 < 4.0 * r1);
}

test "input rejection: zero cycle time" {
    try std.testing.expectError(Error.NonPositiveRate, netMovesPerHour(0.0, 1.0, 0.0));
}

test "input rejection: loss fraction >= 1" {
    try std.testing.expectError(Error.InvalidLossFraction, netMovesPerHour(90.0, 1.0, 1.0));
}

test "input rejection: zero crane count" {
    try std.testing.expectError(Error.NonPositiveCount, multiCraneEfficiency(0, 0.10));
}
