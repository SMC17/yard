const std = @import("std");

pub const Error = error{
    NonPositiveRate,
    NonPositiveDuration,
    InvalidFraction,
};

/// Little's Law for the yard stack:
///   N = lambda * t_dwell
/// where lambda is the arrival rate (TEU/hr), t_dwell is the average
/// dwell time (hr), and N is the time-averaged TEU in yard.
pub fn littleLawAverageInYard(
    lambda_per_hr: f64,
    t_dwell_hr: f64,
) Error!f64 {
    if (!(lambda_per_hr > 0)) return Error.NonPositiveRate;
    if (!(t_dwell_hr > 0)) return Error.NonPositiveDuration;
    return lambda_per_hr * t_dwell_hr;
}

/// Yard slot requirement at given stack density (TEU per ground
/// slot):
///   slots = N / density.
pub fn yardSlotsRequired(
    N_teu_in_yard: f64,
    stack_density: f64,
) Error!f64 {
    if (!(N_teu_in_yard > 0)) return Error.NonPositiveRate;
    if (!(stack_density > 0)) return Error.NonPositiveDuration;
    return N_teu_in_yard / stack_density;
}

/// Dwell-time mix: import / export / transhipment fractions sum to
/// 1.0. Weighted average dwell time:
///   t_dwell = sum(f_i * t_i).
pub const DwellMix = struct {
    import_fraction: f64,
    export_fraction: f64,
    transship_fraction: f64,
    t_import_hr: f64,
    t_export_hr: f64,
    t_transship_hr: f64,
};

pub fn weightedDwellHr(mix: DwellMix) Error!f64 {
    if (!(mix.import_fraction >= 0)) return Error.InvalidFraction;
    if (!(mix.export_fraction >= 0)) return Error.InvalidFraction;
    if (!(mix.transship_fraction >= 0)) return Error.InvalidFraction;
    const sum = mix.import_fraction + mix.export_fraction + mix.transship_fraction;
    if (@abs(sum - 1.0) > 1e-9) return Error.InvalidFraction;
    if (!(mix.t_import_hr > 0)) return Error.NonPositiveDuration;
    if (!(mix.t_export_hr > 0)) return Error.NonPositiveDuration;
    if (!(mix.t_transship_hr > 0)) return Error.NonPositiveDuration;
    return mix.import_fraction * mix.t_import_hr +
        mix.export_fraction * mix.t_export_hr +
        mix.transship_fraction * mix.t_transship_hr;
}

/// Annual containers per ground slot:
///   moves_per_slot = (8760 / t_dwell) * stack_density.
pub fn annualMovesPerGroundSlot(
    t_dwell_hr: f64,
    stack_density: f64,
) Error!f64 {
    if (!(t_dwell_hr > 0)) return Error.NonPositiveDuration;
    if (!(stack_density > 0)) return Error.NonPositiveDuration;
    return (8760.0 / t_dwell_hr) * stack_density;
}

test "Little's Law: 100 TEU/hr * 72 hr dwell = 7200 TEU in yard" {
    const N = try littleLawAverageInYard(100.0, 72.0);
    try std.testing.expectApproxEqAbs(@as(f64, 7200.0), N, 1e-3);
}

test "Little's Law scales linearly with arrival rate" {
    const N1 = try littleLawAverageInYard(100.0, 72.0);
    const N2 = try littleLawAverageInYard(200.0, 72.0);
    try std.testing.expectApproxEqAbs(2.0, N2 / N1, 1e-9);
}

test "yard slots: 7200 TEU / density 3.5 = 2057 slots" {
    const s = try yardSlotsRequired(7200.0, 3.5);
    try std.testing.expectApproxEqAbs(@as(f64, 7200.0 / 3.5), s, 1e-6);
}

test "yard slots scale inversely with stack density" {
    const s1 = try yardSlotsRequired(7200.0, 3.5);
    const s2 = try yardSlotsRequired(7200.0, 7.0);
    try std.testing.expectApproxEqAbs(0.5, s2 / s1, 1e-9);
}

test "weighted dwell: 60% import 72h, 30% export 96h, 10% transship 48h" {
    const t = try weightedDwellHr(.{
        .import_fraction = 0.6,
        .export_fraction = 0.3,
        .transship_fraction = 0.1,
        .t_import_hr = 72.0,
        .t_export_hr = 96.0,
        .t_transship_hr = 48.0,
    });
    const expected = 0.6 * 72.0 + 0.3 * 96.0 + 0.1 * 48.0;
    try std.testing.expectApproxEqAbs(expected, t, 1e-9);
}

test "weighted dwell: pure transshipment gives transship time" {
    const t = try weightedDwellHr(.{
        .import_fraction = 0.0,
        .export_fraction = 0.0,
        .transship_fraction = 1.0,
        .t_import_hr = 72.0,
        .t_export_hr = 96.0,
        .t_transship_hr = 48.0,
    });
    try std.testing.expectApproxEqAbs(@as(f64, 48.0), t, 1e-12);
}

test "annual moves per slot: 8760 / 72 * 3.5 = 425.8" {
    const m = try annualMovesPerGroundSlot(72.0, 3.5);
    try std.testing.expectApproxEqAbs(@as(f64, 8760.0 / 72.0 * 3.5), m, 1e-3);
}

test "annual moves per slot scales linearly with density" {
    const m1 = try annualMovesPerGroundSlot(72.0, 3.5);
    const m2 = try annualMovesPerGroundSlot(72.0, 7.0);
    try std.testing.expectApproxEqAbs(2.0, m2 / m1, 1e-9);
}

test "annual moves per slot scales inversely with dwell" {
    const m1 = try annualMovesPerGroundSlot(72.0, 3.5);
    const m2 = try annualMovesPerGroundSlot(144.0, 3.5);
    try std.testing.expectApproxEqAbs(0.5, m2 / m1, 1e-9);
}

test "input rejection: zero rate" {
    try std.testing.expectError(Error.NonPositiveRate, littleLawAverageInYard(0.0, 72.0));
}

test "input rejection: mix sums to != 1" {
    try std.testing.expectError(
        Error.InvalidFraction,
        weightedDwellHr(.{
            .import_fraction = 0.5,
            .export_fraction = 0.4,
            .transship_fraction = 0.0,
            .t_import_hr = 72.0,
            .t_export_hr = 96.0,
            .t_transship_hr = 48.0,
        }),
    );
}
