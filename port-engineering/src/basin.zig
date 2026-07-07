const std = @import("std");

pub const Error = error{
    NonPositiveArea,
    NonPositiveLength,
    NonPositiveDepth,
    NonPositiveMode,
};

/// Helmholtz natural period of a coupled basin-channel system:
///   T_H = 2 pi sqrt(A_basin L_channel / (g A_channel))
/// where A_basin is the basin water-plane area, L_channel is the
/// connecting-channel length, and A_channel is the cross-sectional
/// area of the channel.
pub fn helmholtzPeriodSec(
    A_basin_m2: f64,
    L_channel_m: f64,
    A_channel_m2: f64,
    g_mps2: f64,
) Error!f64 {
    if (!(A_basin_m2 > 0)) return Error.NonPositiveArea;
    if (!(L_channel_m > 0)) return Error.NonPositiveLength;
    if (!(A_channel_m2 > 0)) return Error.NonPositiveArea;
    return 2.0 * std.math.pi *
        @sqrt(A_basin_m2 * L_channel_m / (g_mps2 * A_channel_m2));
}

/// Open-end open-end (open-mouth) rectangular basin seiche period
/// for mode n per Merian formula:
///   T_n = 2 L / (n sqrt(g h))   for closed-closed
///   T_n = 4 L / ((2 n - 1) sqrt(g h))   for closed-open ends.
pub fn seichePeriodClosedClosedSec(
    L_basin_m: f64,
    h_m: f64,
    mode_n: u32,
    g_mps2: f64,
) Error!f64 {
    if (!(L_basin_m > 0)) return Error.NonPositiveLength;
    if (!(h_m > 0)) return Error.NonPositiveDepth;
    if (mode_n == 0) return Error.NonPositiveMode;
    const n_f: f64 = @floatFromInt(mode_n);
    return 2.0 * L_basin_m / (n_f * @sqrt(g_mps2 * h_m));
}

pub fn seichePeriodClosedOpenSec(
    L_basin_m: f64,
    h_m: f64,
    mode_n: u32,
    g_mps2: f64,
) Error!f64 {
    if (!(L_basin_m > 0)) return Error.NonPositiveLength;
    if (!(h_m > 0)) return Error.NonPositiveDepth;
    if (mode_n == 0) return Error.NonPositiveMode;
    const n_f: f64 = @floatFromInt(mode_n);
    return 4.0 * L_basin_m / ((2.0 * n_f - 1.0) * @sqrt(g_mps2 * h_m));
}

/// Resonance check: a harbour-forcing period T_forcing matching a
/// natural period within 5 % is flagged as a potential resonance.
pub fn resonanceVerdict(T_natural_sec: f64, T_forcing_sec: f64) bool {
    if (T_natural_sec <= 0 or T_forcing_sec <= 0) return false;
    const rel = @abs(T_natural_sec - T_forcing_sec) / T_natural_sec;
    return rel < 0.05;
}

test "Helmholtz period closed form" {
    // A_basin = 200000 m^2, L_channel = 200 m, A_channel = 4000 m^2.
    const T = try helmholtzPeriodSec(200_000.0, 200.0, 4000.0, 9.81);
    const expected = 2.0 * std.math.pi * @sqrt(@as(f64, 200_000.0 * 200.0 / (9.81 * 4000.0)));
    try std.testing.expectApproxEqAbs(expected, T, 1e-9);
}

test "Helmholtz period scales with sqrt(A_basin)" {
    const T1 = try helmholtzPeriodSec(100_000.0, 200.0, 4000.0, 9.81);
    const T2 = try helmholtzPeriodSec(400_000.0, 200.0, 4000.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), T2 / T1, 1e-9);
}

test "Helmholtz period inversely proportional to sqrt(A_channel)" {
    const T1 = try helmholtzPeriodSec(200_000.0, 200.0, 1000.0, 9.81);
    const T2 = try helmholtzPeriodSec(200_000.0, 200.0, 4000.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), T2 / T1, 1e-9);
}

test "Seiche closed-closed mode 1: T = 2 L / sqrt(g h)" {
    const T = try seichePeriodClosedClosedSec(1000.0, 10.0, 1, 9.81);
    const expected = 2.0 * 1000.0 / @sqrt(@as(f64, 9.81 * 10.0));
    try std.testing.expectApproxEqAbs(expected, T, 1e-9);
}

test "Seiche closed-closed mode 2 is half of mode 1" {
    const T_1 = try seichePeriodClosedClosedSec(1000.0, 10.0, 1, 9.81);
    const T_2 = try seichePeriodClosedClosedSec(1000.0, 10.0, 2, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), T_2 / T_1, 1e-9);
}

test "Seiche closed-open mode 1: T = 4 L / sqrt(g h)" {
    const T = try seichePeriodClosedOpenSec(1000.0, 10.0, 1, 9.81);
    const expected = 4.0 * 1000.0 / @sqrt(@as(f64, 9.81 * 10.0));
    try std.testing.expectApproxEqAbs(expected, T, 1e-9);
}

test "Closed-open mode 1 is twice closed-closed mode 1" {
    const T_cc = try seichePeriodClosedClosedSec(1000.0, 10.0, 1, 9.81);
    const T_co = try seichePeriodClosedOpenSec(1000.0, 10.0, 1, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), T_co / T_cc, 1e-9);
}

test "Resonance flagged within 5%" {
    try std.testing.expectEqual(true, resonanceVerdict(120.0, 122.0));
    try std.testing.expectEqual(false, resonanceVerdict(120.0, 130.0));
}

test "Resonance returns false on invalid input" {
    try std.testing.expectEqual(false, resonanceVerdict(0.0, 122.0));
    try std.testing.expectEqual(false, resonanceVerdict(120.0, 0.0));
}

test "input rejection: zero A_basin" {
    try std.testing.expectError(Error.NonPositiveArea, helmholtzPeriodSec(0.0, 200.0, 4000.0, 9.81));
}

test "input rejection: zero L_basin in seiche" {
    try std.testing.expectError(
        Error.NonPositiveLength,
        seichePeriodClosedClosedSec(0.0, 10.0, 1, 9.81),
    );
}

test "input rejection: zero mode_n" {
    try std.testing.expectError(
        Error.NonPositiveMode,
        seichePeriodClosedOpenSec(1000.0, 10.0, 0, 9.81),
    );
}
