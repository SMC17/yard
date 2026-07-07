const std = @import("std");
const eedi = @import("src/eedi.zig");

pub fn main() !void {
    std.debug.print("Starting EEDI Stress Tests...\n", .{});
    
    try testNaNRejection();
    try testInfRejectionAndHandling();
    try testNegativeZeroRejection();
    try testSubnormalAndUnderflow();
    try testOverflow();
    try testVerdictNaNAndInf();
    
    std.debug.print("All EEDI Stress Tests Passed Successfully!\n", .{});
}

fn testNaNRejection() !void {
    const nan = std.math.nan(f64);
    
    // 1. NaN Capacity
    const in_nan_capacity: eedi.EEDIInputs = .{
        .main_engines = &[_]eedi.Engine{},
        .auxiliary_engines = &[_]eedi.Engine{},
        .capacity_t = nan,
        .V_ref_kt = 15.0,
        .f_i = 1.0,
    };
    try std.testing.expectError(eedi.Error.NonPositiveCapacity, eedi.attainedValueGCO2PerTNm(in_nan_capacity));
    
    // 2. NaN Speed
    const in_nan_speed: eedi.EEDIInputs = .{
        .main_engines = &[_]eedi.Engine{},
        .auxiliary_engines = &[_]eedi.Engine{},
        .capacity_t = 50000.0,
        .V_ref_kt = nan,
        .f_i = 1.0,
    };
    try std.testing.expectError(eedi.Error.NonPositiveSpeed, eedi.attainedValueGCO2PerTNm(in_nan_speed));

    // 3. NaN Correction Factor f_i
    const in_nan_fi: eedi.EEDIInputs = .{
        .main_engines = &[_]eedi.Engine{},
        .auxiliary_engines = &[_]eedi.Engine{},
        .capacity_t = 50000.0,
        .V_ref_kt = 15.0,
        .f_i = nan,
    };
    try std.testing.expectError(eedi.Error.InvalidCorrectionFactor, eedi.attainedValueGCO2PerTNm(in_nan_fi));

    // 4. NaN Engine Power
    const me_nan_power = [_]eedi.Engine{.{ .P_kw = nan, .SFC_g_per_kwh = 190.0, .fuel = .HFO }};
    const in_nan_power: eedi.EEDIInputs = .{
        .main_engines = &me_nan_power,
        .auxiliary_engines = &[_]eedi.Engine{},
        .capacity_t = 50000.0,
        .V_ref_kt = 15.0,
        .f_i = 1.0,
    };
    try std.testing.expectError(eedi.Error.NonPositivePower, eedi.attainedValueGCO2PerTNm(in_nan_power));

    // 5. NaN SFC
    const me_nan_sfc = [_]eedi.Engine{.{ .P_kw = 10000.0, .SFC_g_per_kwh = nan, .fuel = .HFO }};
    const in_nan_sfc: eedi.EEDIInputs = .{
        .main_engines = &me_nan_sfc,
        .auxiliary_engines = &[_]eedi.Engine{},
        .capacity_t = 50000.0,
        .V_ref_kt = 15.0,
        .f_i = 1.0,
    };
    try std.testing.expectError(eedi.Error.NonPositiveSfc, eedi.attainedValueGCO2PerTNm(in_nan_sfc));

    // 6. NaN Baseline
    try std.testing.expectError(eedi.Error.NonPositiveBaseline, eedi.requiredValueGCO2PerTNm(nan, .phase_2));
}

fn testInfRejectionAndHandling() !void {
    const inf = std.math.inf(f64);
    const neg_inf = -std.math.inf(f64);

    // Negative Infinity rejection
    const in_neg_inf_capacity: eedi.EEDIInputs = .{
        .main_engines = &[_]eedi.Engine{},
        .auxiliary_engines = &[_]eedi.Engine{},
        .capacity_t = neg_inf,
        .V_ref_kt = 15.0,
        .f_i = 1.0,
    };
    try std.testing.expectError(eedi.Error.NonPositiveCapacity, eedi.attainedValueGCO2PerTNm(in_neg_inf_capacity));

    // Positive Infinity handling
    // 1. Inf Capacity => attained EEDI should be 0.0 (since num is finite, denom is inf)
    const me = [_]eedi.Engine{.{ .P_kw = 10000.0, .SFC_g_per_kwh = 190.0, .fuel = .HFO }};
    const in_inf_capacity: eedi.EEDIInputs = .{
        .main_engines = &me,
        .auxiliary_engines = &[_]eedi.Engine{},
        .capacity_t = inf,
        .V_ref_kt = 15.0,
        .f_i = 1.0,
    };
    const val_inf_cap = try eedi.attainedValueGCO2PerTNm(in_inf_capacity);
    try std.testing.expectEqual(@as(f64, 0.0), val_inf_cap);

    // 2. Inf Power => attained EEDI should be inf (num is inf, denom is finite)
    const me_inf_power = [_]eedi.Engine{.{ .P_kw = inf, .SFC_g_per_kwh = 190.0, .fuel = .HFO }};
    const in_inf_power: eedi.EEDIInputs = .{
        .main_engines = &me_inf_power,
        .auxiliary_engines = &[_]eedi.Engine{},
        .capacity_t = 50000.0,
        .V_ref_kt = 15.0,
        .f_i = 1.0,
    };
    const val_inf_power = try eedi.attainedValueGCO2PerTNm(in_inf_power);
    try std.testing.expect(std.math.isInf(val_inf_power) and val_inf_power > 0);

    // 3. Inf Baseline => required EEDI should be inf
    const req_inf_baseline = try eedi.requiredValueGCO2PerTNm(inf, .phase_2);
    try std.testing.expect(std.math.isInf(req_inf_baseline) and req_inf_baseline > 0);
}

fn testNegativeZeroRejection() !void {
    const neg_zero = -0.0;
    
    // -0.0 capacity is not > 0, so should be rejected
    const in_neg_zero_capacity: eedi.EEDIInputs = .{
        .main_engines = &[_]eedi.Engine{},
        .auxiliary_engines = &[_]eedi.Engine{},
        .capacity_t = neg_zero,
        .V_ref_kt = 15.0,
        .f_i = 1.0,
    };
    try std.testing.expectError(eedi.Error.NonPositiveCapacity, eedi.attainedValueGCO2PerTNm(in_neg_zero_capacity));

    // -0.0 baseline is not > 0
    try std.testing.expectError(eedi.Error.NonPositiveBaseline, eedi.requiredValueGCO2PerTNm(neg_zero, .phase_2));
}

fn testSubnormalAndUnderflow() !void {
    // Subnormal numbers or extremely small floats
    const tiny = 1e-300; // very small but normal/subnormal
    
    // Denominator underflow to 0.0 when using extremely small capacity and speed
    const in_tiny_denom: eedi.EEDIInputs = .{
        .main_engines = &[_]eedi.Engine{.{ .P_kw = 1.0, .SFC_g_per_kwh = 100.0, .fuel = .HFO }},
        .auxiliary_engines = &[_]eedi.Engine{},
        .capacity_t = tiny,
        .V_ref_kt = tiny,
        .f_i = 1.0,
    };
    
    // tiny * tiny underflows to 0.0 in f64
    const val = try eedi.attainedValueGCO2PerTNm(in_tiny_denom);
    // Division by 0.0 for positive numerator returns +inf in IEEE-754
    try std.testing.expect(std.math.isInf(val) and val > 0);
}

fn testOverflow() !void {
    const max_f64 = std.math.floatMax(f64);
    
    // Large inputs that cause overflow to inf
    const me = [_]eedi.Engine{.{ .P_kw = max_f64, .SFC_g_per_kwh = max_f64, .fuel = .HFO }};
    const in: eedi.EEDIInputs = .{
        .main_engines = &me,
        .auxiliary_engines = &[_]eedi.Engine{},
        .capacity_t = 1.0,
        .V_ref_kt = 1.0,
        .f_i = 1.0,
    };
    const val = try eedi.attainedValueGCO2PerTNm(in);
    try std.testing.expect(std.math.isInf(val) and val > 0);
}

fn testVerdictNaNAndInf() !void {
    const nan = std.math.nan(f64);
    const inf = std.math.inf(f64);
    
    // NaN in attained or required should fail the verdict
    try std.testing.expectEqual(eedi.Verdict.fail, eedi.verdict(nan, 10.0));
    try std.testing.expectEqual(eedi.Verdict.fail, eedi.verdict(10.0, nan));
    try std.testing.expectEqual(eedi.Verdict.fail, eedi.verdict(nan, nan));

    // +inf attained should fail unless required is also +inf (since inf <= inf is true)
    try std.testing.expectEqual(eedi.Verdict.fail, eedi.verdict(inf, 10.0));
    try std.testing.expectEqual(eedi.Verdict.pass, eedi.verdict(inf, inf));
    try std.testing.expectEqual(eedi.Verdict.pass, eedi.verdict(10.0, inf));
}
