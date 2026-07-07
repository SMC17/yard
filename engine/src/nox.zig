const std = @import("std");

pub const Error = error{
    NonPositiveSpeed,
    InvalidTier,
};

pub const NoxTier = enum {
    Tier_I,
    Tier_II,
    Tier_III,
};

/// IMO MARPOL Annex VI weighted NOx limit in g / kWh as a function of
/// rated engine speed `n` in rpm. Per Regulation 13:
///
///   Tier I  (engines installed 1 Jan 2000 - 1 Jan 2011):
///     17.0                  for n < 130
///     45 n^(-0.2)           for 130 <= n <= 2000
///     9.8                   for n > 2000
///
///   Tier II (engines installed on or after 1 Jan 2011):
///     14.4
///     44 n^(-0.23)
///     7.7
///
///   Tier III (engines installed on or after 1 Jan 2016 in ECAs):
///     3.4
///     9 n^(-0.2)
///     2.0
pub fn weightedLimitGPerKwh(tier: NoxTier, n_rpm: f64) Error!f64 {
    if (!(n_rpm > 0)) return Error.NonPositiveSpeed;
    return switch (tier) {
        .Tier_I => blk: {
            if (n_rpm < 130.0) break :blk 17.0;
            if (n_rpm > 2000.0) break :blk 9.8;
            break :blk 45.0 * std.math.pow(f64, n_rpm, -0.2);
        },
        .Tier_II => blk: {
            if (n_rpm < 130.0) break :blk 14.4;
            if (n_rpm > 2000.0) break :blk 7.7;
            break :blk 44.0 * std.math.pow(f64, n_rpm, -0.23);
        },
        .Tier_III => blk: {
            if (n_rpm < 130.0) break :blk 3.4;
            if (n_rpm > 2000.0) break :blk 2.0;
            break :blk 9.0 * std.math.pow(f64, n_rpm, -0.2);
        },
    };
}

pub const Verdict = enum { pass, fail };

pub fn verdict(emission_g_per_kwh: f64, limit_g_per_kwh: f64) Verdict {
    if (emission_g_per_kwh <= limit_g_per_kwh) return .pass;
    return .fail;
}

test "Tier I limit at n = 100 rpm is 17.0 g/kWh" {
    const v = try weightedLimitGPerKwh(.Tier_I, 100.0);
    try std.testing.expectApproxEqAbs(@as(f64, 17.0), v, 1e-12);
}

test "Tier I limit at n = 2500 rpm is 9.8 g/kWh" {
    const v = try weightedLimitGPerKwh(.Tier_I, 2500.0);
    try std.testing.expectApproxEqAbs(@as(f64, 9.8), v, 1e-12);
}

test "Tier I limit at n = 720 rpm matches 45 n^(-0.2)" {
    const v = try weightedLimitGPerKwh(.Tier_I, 720.0);
    const expected = 45.0 * std.math.pow(f64, 720.0, -0.2);
    try std.testing.expectApproxEqAbs(expected, v, 1e-12);
}

test "Tier II at 720 rpm < Tier I" {
    const v_I = try weightedLimitGPerKwh(.Tier_I, 720.0);
    const v_II = try weightedLimitGPerKwh(.Tier_II, 720.0);
    try std.testing.expect(v_II < v_I);
}

test "Tier III at 720 rpm < Tier II" {
    const v_II = try weightedLimitGPerKwh(.Tier_II, 720.0);
    const v_III = try weightedLimitGPerKwh(.Tier_III, 720.0);
    try std.testing.expect(v_III < v_II);
}

test "Tier III at n = 720 is 9 n^(-0.2) ~ 2.45 g/kWh" {
    const v = try weightedLimitGPerKwh(.Tier_III, 720.0);
    const expected = 9.0 * std.math.pow(f64, 720.0, -0.2);
    try std.testing.expectApproxEqAbs(expected, v, 1e-12);
}

test "verdict: emission below limit passes" {
    try std.testing.expectEqual(Verdict.pass, verdict(7.5, 10.0));
}

test "verdict: emission at limit passes" {
    try std.testing.expectEqual(Verdict.pass, verdict(10.0, 10.0));
}

test "verdict: emission above limit fails" {
    try std.testing.expectEqual(Verdict.fail, verdict(10.5, 10.0));
}

test "input rejection: zero engine speed" {
    try std.testing.expectError(Error.NonPositiveSpeed, weightedLimitGPerKwh(.Tier_II, 0.0));
}
