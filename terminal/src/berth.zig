const std = @import("std");

pub const Error = error{
    NonPositiveDuration,
    NonPositiveBerthCount,
    InvalidUtilisation,
};

/// Per-call service time for a vessel:
///   t_service = TEU_call / (cranes_per_vessel * moves_per_hour) +
///               t_pilot_tug + t_mooring + t_unmooring.
pub fn serviceTimeHr(
    TEU_call: f64,
    cranes_per_vessel: u32,
    moves_per_hour_per_crane: f64,
    fixed_overhead_hr: f64,
) Error!f64 {
    if (!(TEU_call > 0)) return Error.NonPositiveDuration;
    if (cranes_per_vessel == 0) return Error.NonPositiveBerthCount;
    if (!(moves_per_hour_per_crane > 0)) return Error.NonPositiveDuration;
    if (!(fixed_overhead_hr >= 0)) return Error.NonPositiveDuration;
    const n_f: f64 = @floatFromInt(cranes_per_vessel);
    return TEU_call / (n_f * moves_per_hour_per_crane) + fixed_overhead_hr;
}

/// Berth utilisation:
///   rho = (annual_calls * average_service_hr) / (berth_count * 8760).
pub fn berthUtilisation(
    annual_calls: u32,
    average_service_hr: f64,
    berth_count: u32,
) Error!f64 {
    if (annual_calls == 0) return Error.NonPositiveDuration;
    if (!(average_service_hr > 0)) return Error.NonPositiveDuration;
    if (berth_count == 0) return Error.NonPositiveBerthCount;
    const ac_f: f64 = @floatFromInt(annual_calls);
    const bc_f: f64 = @floatFromInt(berth_count);
    return ac_f * average_service_hr / (bc_f * 8760.0);
}

/// Annual berth-throughput capacity at a target utilisation:
///   calls = rho_target * berth_count * 8760 / service_hr.
pub fn annualCapacityCalls(
    average_service_hr: f64,
    berth_count: u32,
    rho_target: f64,
) Error!f64 {
    if (!(average_service_hr > 0)) return Error.NonPositiveDuration;
    if (berth_count == 0) return Error.NonPositiveBerthCount;
    if (!(rho_target > 0.0 and rho_target <= 1.0)) return Error.InvalidUtilisation;
    const bc_f: f64 = @floatFromInt(berth_count);
    return rho_target * bc_f * 8760.0 / average_service_hr;
}

pub const Verdict = enum { undercapacity, ok, overcapacity };

/// Operational verdict against a 0.55-0.70 sweet-spot utilisation
/// band (UNCTAD 2004 benchmark for container terminals).
pub fn utilisationVerdict(rho: f64) Verdict {
    if (rho < 0.55) return .undercapacity;
    if (rho > 0.70) return .overcapacity;
    return .ok;
}

test "service time: 3000 TEU, 4 cranes at 30 mph + 4 h overhead" {
    const t = try serviceTimeHr(3000.0, 4, 30.0, 4.0);
    // 3000 / 120 + 4 = 25 + 4 = 29 h.
    try std.testing.expectApproxEqAbs(@as(f64, 29.0), t, 1e-9);
}

test "service time scales inversely with crane count" {
    const t_2 = try serviceTimeHr(3000.0, 2, 30.0, 0.0);
    const t_4 = try serviceTimeHr(3000.0, 4, 30.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), t_2 / t_4, 1e-9);
}

test "service time scales linearly with TEU" {
    const t_1k = try serviceTimeHr(1000.0, 4, 30.0, 0.0);
    const t_3k = try serviceTimeHr(3000.0, 4, 30.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), t_3k / t_1k, 1e-9);
}

test "berth utilisation: 1000 calls * 24 h / (4 berths * 8760)" {
    const rho = try berthUtilisation(1000, 24.0, 4);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1000.0 * 24.0 / (4.0 * 8760.0)),
        rho,
        1e-12,
    );
}

test "annual capacity at rho = 0.65, 24 h service, 4 berths" {
    const calls = try annualCapacityCalls(24.0, 4, 0.65);
    // 0.65 * 4 * 8760 / 24 = 949 calls.
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.65 * 4.0 * 8760.0 / 24.0),
        calls,
        1e-9,
    );
}

test "annual capacity scales linearly with berth count" {
    const c_2 = try annualCapacityCalls(24.0, 2, 0.65);
    const c_4 = try annualCapacityCalls(24.0, 4, 0.65);
    try std.testing.expectApproxEqAbs(2.0 * c_2, c_4, 1e-9);
}

test "verdict undercapacity at rho = 0.40" {
    try std.testing.expectEqual(Verdict.undercapacity, utilisationVerdict(0.40));
}

test "verdict ok at rho = 0.62" {
    try std.testing.expectEqual(Verdict.ok, utilisationVerdict(0.62));
}

test "verdict overcapacity at rho = 0.80" {
    try std.testing.expectEqual(Verdict.overcapacity, utilisationVerdict(0.80));
}

test "verdict at exact 0.55 lower boundary returns ok" {
    try std.testing.expectEqual(Verdict.ok, utilisationVerdict(0.55));
}

test "verdict at exact 0.70 upper boundary returns ok" {
    try std.testing.expectEqual(Verdict.ok, utilisationVerdict(0.70));
}

test "input rejection: zero cranes" {
    try std.testing.expectError(Error.NonPositiveBerthCount, serviceTimeHr(1000.0, 0, 30.0, 4.0));
}

test "input rejection: rho_target > 1" {
    try std.testing.expectError(
        Error.InvalidUtilisation,
        annualCapacityCalls(24.0, 4, 1.5),
    );
}

test "input rejection: zero calls" {
    try std.testing.expectError(Error.NonPositiveDuration, berthUtilisation(0, 24.0, 4));
}
