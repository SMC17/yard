const std = @import("std");

pub const Error = error{
    NonPositiveRate,
    NonPositiveCount,
    InvalidFraction,
};

/// Annual TEU throughput from N berths each running B hours/year at
/// per-berth crane productivity P [TEU/hr]:
///   TEU/year = N * B * P.
pub fn annualThroughputTEU(
    N_berths: u32,
    hours_per_berth_per_year: f64,
    teu_per_hour_per_berth: f64,
) Error!f64 {
    if (N_berths == 0) return Error.NonPositiveCount;
    if (!(hours_per_berth_per_year > 0)) return Error.NonPositiveRate;
    if (!(teu_per_hour_per_berth > 0)) return Error.NonPositiveRate;
    const N_f: f64 = @floatFromInt(N_berths);
    return N_f * hours_per_berth_per_year * teu_per_hour_per_berth;
}

/// Effective hours per berth per year:
///   hours_effective = 8760 * utilisation_fraction * (1 - downtime_fraction).
pub fn effectiveBerthHoursPerYear(
    utilisation: f64,
    downtime_fraction: f64,
) Error!f64 {
    if (!(utilisation > 0 and utilisation <= 1.0)) return Error.InvalidFraction;
    if (!(downtime_fraction >= 0 and downtime_fraction < 1.0)) return Error.InvalidFraction;
    return 8760.0 * utilisation * (1.0 - downtime_fraction);
}

/// Moves per crane-hour at given productivity x dual-cycling x
/// loss:
///   moves = base_mph * uplift * (1 - loss).
pub fn movesPerHour(
    base_mph: f64,
    dual_cycling_uplift: f64,
    loss_fraction: f64,
) Error!f64 {
    if (!(base_mph > 0)) return Error.NonPositiveRate;
    if (!(dual_cycling_uplift >= 1.0)) return Error.NonPositiveRate;
    if (!(loss_fraction >= 0 and loss_fraction < 1.0)) return Error.InvalidFraction;
    return base_mph * dual_cycling_uplift * (1.0 - loss_fraction);
}

/// Throughput per metre of quay: industry benchmark ~ 1500
/// TEU/m/year for high-performing super-post-Panamax terminals.
pub fn throughputPerQuayMeter(
    annual_teu: f64,
    quay_length_m: f64,
) Error!f64 {
    if (!(annual_teu > 0)) return Error.NonPositiveRate;
    if (!(quay_length_m > 0)) return Error.NonPositiveCount;
    return annual_teu / quay_length_m;
}

test "annual throughput: 4 berths * 5000 h * 80 TEU/h = 1.6 M TEU" {
    const T = try annualThroughputTEU(4, 5000.0, 80.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1_600_000.0), T, 1e-3);
}

test "annual throughput scales linearly with N berths" {
    const t1 = try annualThroughputTEU(2, 5000.0, 80.0);
    const t2 = try annualThroughputTEU(4, 5000.0, 80.0);
    try std.testing.expectApproxEqAbs(2.0, t2 / t1, 1e-9);
}

test "effective berth hours at u=0.65, downtime=0.10: 5117 hr" {
    const h = try effectiveBerthHoursPerYear(0.65, 0.10);
    const expected = 8760.0 * 0.65 * 0.90;
    try std.testing.expectApproxEqAbs(expected, h, 1e-6);
}

test "effective hours at 100% utilisation = 8760 (1 - downtime)" {
    const h = try effectiveBerthHoursPerYear(1.0, 0.10);
    try std.testing.expectApproxEqAbs(@as(f64, 8760.0 * 0.90), h, 1e-9);
}

test "moves per hour: 30 base * 1.25 dual * 0.90 loss = 33.75" {
    const m = try movesPerHour(30.0, 1.25, 0.10);
    try std.testing.expectApproxEqAbs(@as(f64, 33.75), m, 1e-9);
}

test "throughput per quay meter: 1.6 M TEU / 1000 m = 1600 TEU/m" {
    const t = try throughputPerQuayMeter(1_600_000.0, 1000.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1600.0), t, 1e-9);
}

test "input rejection: zero berths" {
    try std.testing.expectError(
        Error.NonPositiveCount,
        annualThroughputTEU(0, 5000.0, 80.0),
    );
}

test "input rejection: utilisation > 1" {
    try std.testing.expectError(
        Error.InvalidFraction,
        effectiveBerthHoursPerYear(1.5, 0.10),
    );
}

test "input rejection: downtime >= 1" {
    try std.testing.expectError(
        Error.InvalidFraction,
        effectiveBerthHoursPerYear(0.65, 1.0),
    );
}

test "input rejection: zero base mph" {
    try std.testing.expectError(Error.NonPositiveRate, movesPerHour(0.0, 1.25, 0.10));
}

test "input rejection: dual-cycling < 1" {
    try std.testing.expectError(Error.NonPositiveRate, movesPerHour(30.0, 0.9, 0.10));
}
