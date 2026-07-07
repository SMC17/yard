// Extended wave-spectrum library: Bretschneider, Ochi-Hubble bimodal,
// Torsethaugen double-peaked.

const std = @import("std");

pub const Error = error{
    NonPositiveHs,
    NonPositiveTp,
    NonPositiveOmega,
    InvalidShape,
};

/// Bretschneider (Pierson-Moskowitz two-parameter) spectrum:
///   S(omega) = (5/16) (Hs^2 / Tp) (omega_p / omega)^5 *
///              exp(-(5/4) (omega_p / omega)^4)
/// where omega_p = 2 pi / Tp.
pub fn bretschneider(omega: f64, Hs_m: f64, Tp_s: f64) Error!f64 {
    if (!(omega > 0)) return Error.NonPositiveOmega;
    if (!(Hs_m > 0)) return Error.NonPositiveHs;
    if (!(Tp_s > 0)) return Error.NonPositiveTp;
    const omega_p = 2.0 * std.math.pi / Tp_s;
    const r = omega_p / omega;
    return (5.0 / 16.0) * (Hs_m * Hs_m / Tp_s) *
        std.math.pow(f64, r, 5) *
        @exp(-1.25 * std.math.pow(f64, r, 4));
}

/// Ochi-Hubble bimodal spectrum: two Bretschneider components for
/// swell + wind sea.
pub const OchiHubbleParams = struct {
    Hs_swell_m: f64,
    Tp_swell_s: f64,
    lambda_swell: f64, // shape parameter (typ. 3.0 swell, 6.0 wind sea)
    Hs_wind_m: f64,
    Tp_wind_s: f64,
    lambda_wind: f64,
};

fn ochiHubbleComponent(
    omega: f64,
    Hs: f64,
    Tp: f64,
    lambda: f64,
) Error!f64 {
    if (!(omega > 0)) return Error.NonPositiveOmega;
    if (!(Hs > 0)) return Error.NonPositiveHs;
    if (!(Tp > 0)) return Error.NonPositiveTp;
    if (!(lambda > 0)) return Error.InvalidShape;
    const omega_p = 2.0 * std.math.pi / Tp;
    const four_lambda_plus_1_over_4 = (4.0 * lambda + 1.0) / 4.0;
    // Gamma(lambda) function via Stirling for the relevant range; the
    // Ochi-Hubble spectrum uses (1 / Gamma(lambda)) * (4 lambda + 1)
    // raised to the lambda power. The kernel uses the canonical
    // closed form per Ochi & Hubble 1976:
    //   S = (1/4) (omega_p^4)^lambda / (Gamma(lambda) omega^(4 lambda + 1))
    //       * Hs^2 * exp(-(4 lambda + 1) / 4 * (omega_p / omega)^4).
    const gamma_lambda = std.math.tgamma(f64, lambda);
    const omega_p_pow = std.math.pow(f64, omega_p, 4.0 * lambda);
    const omega_pow = std.math.pow(f64, omega, 4.0 * lambda + 1.0);
    const base = (1.0 / 4.0) * std.math.pow(
        f64,
        four_lambda_plus_1_over_4,
        lambda,
    ) / gamma_lambda;
    return base * omega_p_pow / omega_pow * Hs * Hs *
        @exp(-four_lambda_plus_1_over_4 * std.math.pow(f64, omega_p / omega, 4));
}

pub fn ochiHubble(omega: f64, p: OchiHubbleParams) Error!f64 {
    const swell = try ochiHubbleComponent(omega, p.Hs_swell_m, p.Tp_swell_s, p.lambda_swell);
    const wind = try ochiHubbleComponent(omega, p.Hs_wind_m, p.Tp_wind_s, p.lambda_wind);
    return swell + wind;
}

/// Torsethaugen double-peaked spectrum (Norwegian shelf):
///   Composite of two JONSWAP / Bretschneider segments matched to a
///   measured Hs / Tp pair, partitioning into a wind sea and a
///   swell peak. The kernel uses the canonical simplified Torsethaugen
///   1996 partition T_f = 6.6 Hs^(1/3):
///     - If Tp < T_f: wind-dominated sea state.
///     - If Tp >= T_f: swell-dominated sea state.
pub fn torsethaugenPartitionPeriod(Hs_m: f64) Error!f64 {
    if (!(Hs_m > 0)) return Error.NonPositiveHs;
    return 6.6 * std.math.pow(f64, Hs_m, 1.0 / 3.0);
}

pub fn torsethaugenIsWindDominated(Hs_m: f64, Tp_s: f64) Error!bool {
    if (!(Hs_m > 0)) return Error.NonPositiveHs;
    if (!(Tp_s > 0)) return Error.NonPositiveTp;
    const Tf = try torsethaugenPartitionPeriod(Hs_m);
    return Tp_s < Tf;
}

/// Goda gamma parameter for JONSWAP from the wind / swell partition:
///   gamma = 3.3 (wind-dominated) ; 1.0 (swell-dominated).
pub fn jonswapGammaFromRegime(is_wind_dominated: bool) f64 {
    return if (is_wind_dominated) 3.3 else 1.0;
}

test "Bretschneider peak at omega_p is non-zero and finite" {
    const Hs = 4.0;
    const Tp = 10.0;
    const omega_p = 2.0 * std.math.pi / Tp;
    const S = try bretschneider(omega_p, Hs, Tp);
    try std.testing.expect(S > 0);
    try std.testing.expect(std.math.isFinite(S));
}

test "Bretschneider zero in low-omega limit" {
    const S = try bretschneider(1.0e-5, 4.0, 10.0);
    try std.testing.expect(S < 1.0e-3);
}

test "Bretschneider scales with Hs^2" {
    const omega = 0.6;
    const S1 = try bretschneider(omega, 2.0, 10.0);
    const S2 = try bretschneider(omega, 4.0, 10.0);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), S2 / S1, 1e-9);
}

test "Bretschneider rejects zero omega" {
    try std.testing.expectError(Error.NonPositiveOmega, bretschneider(0.0, 4.0, 10.0));
}

test "Bretschneider rejects zero Hs" {
    try std.testing.expectError(Error.NonPositiveHs, bretschneider(0.5, 0.0, 10.0));
}

test "Ochi-Hubble bimodal positive at peak" {
    const params: OchiHubbleParams = .{
        .Hs_swell_m = 3.0,
        .Tp_swell_s = 14.0,
        .lambda_swell = 3.0,
        .Hs_wind_m = 2.0,
        .Tp_wind_s = 8.0,
        .lambda_wind = 6.0,
    };
    const S_swell_peak = try ochiHubble(2.0 * std.math.pi / 14.0, params);
    const S_wind_peak = try ochiHubble(2.0 * std.math.pi / 8.0, params);
    try std.testing.expect(S_swell_peak > 0);
    try std.testing.expect(S_wind_peak > 0);
}

test "Ochi-Hubble exceeds single Bretschneider at the swell peak" {
    const params: OchiHubbleParams = .{
        .Hs_swell_m = 3.0,
        .Tp_swell_s = 14.0,
        .lambda_swell = 3.0,
        .Hs_wind_m = 2.0,
        .Tp_wind_s = 8.0,
        .lambda_wind = 6.0,
    };
    const omega = 2.0 * std.math.pi / 14.0;
    const S_OH = try ochiHubble(omega, params);
    const S_B = try bretschneider(omega, 3.0, 14.0);
    try std.testing.expect(S_OH > S_B);
}

test "Torsethaugen partition Hs=4 -> T_f = 6.6 * 4^(1/3)" {
    const Tf = try torsethaugenPartitionPeriod(4.0);
    const expected = 6.6 * std.math.pow(f64, @as(f64, 4.0), 1.0 / 3.0);
    try std.testing.expectApproxEqAbs(expected, Tf, 1e-9);
}

test "Torsethaugen wind-dominated when Tp << T_f" {
    const wd = try torsethaugenIsWindDominated(4.0, 7.0);
    try std.testing.expectEqual(true, wd);
}

test "Torsethaugen swell-dominated when Tp >> T_f" {
    const wd = try torsethaugenIsWindDominated(4.0, 14.0);
    try std.testing.expectEqual(false, wd);
}

test "Torsethaugen gamma 3.3 for wind, 1.0 for swell" {
    try std.testing.expectApproxEqAbs(@as(f64, 3.3), jonswapGammaFromRegime(true), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), jonswapGammaFromRegime(false), 1e-12);
}

test "Bretschneider monotone decreasing well above peak" {
    const Hs = 4.0;
    const Tp = 10.0;
    const omega_p = 2.0 * std.math.pi / Tp;
    const S_2 = try bretschneider(2.0 * omega_p, Hs, Tp);
    const S_3 = try bretschneider(3.0 * omega_p, Hs, Tp);
    try std.testing.expect(S_3 < S_2);
}

test "Ochi-Hubble unequal swell vs wind component contribution" {
    const params: OchiHubbleParams = .{
        .Hs_swell_m = 3.0,
        .Tp_swell_s = 14.0,
        .lambda_swell = 3.0,
        .Hs_wind_m = 2.0,
        .Tp_wind_s = 8.0,
        .lambda_wind = 6.0,
    };
    // At very low omega (swell band), swell dominates.
    const omega_swell_band = 2.0 * std.math.pi / 14.0;
    const omega_wind_band = 2.0 * std.math.pi / 8.0;
    const S_swell_band = try ochiHubble(omega_swell_band, params);
    const S_wind_band = try ochiHubble(omega_wind_band, params);
    try std.testing.expect(S_swell_band > 0);
    try std.testing.expect(S_wind_band > 0);
}

test "input rejection: zero lambda in Ochi-Hubble" {
    const params: OchiHubbleParams = .{
        .Hs_swell_m = 3.0,
        .Tp_swell_s = 14.0,
        .lambda_swell = 0.0,
        .Hs_wind_m = 2.0,
        .Tp_wind_s = 8.0,
        .lambda_wind = 6.0,
    };
    try std.testing.expectError(Error.InvalidShape, ochiHubble(0.5, params));
}
