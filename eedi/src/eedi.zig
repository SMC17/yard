const std = @import("std");

pub const Error = error{
    NonPositivePower,
    NonPositiveSfc,
    NonPositiveSpeed,
    NonPositiveCapacity,
    InvalidCorrectionFactor,
    NonPositiveBaseline,
};

/// Carbon-content (kgCO2 / kg fuel) per MEPC.337(76). Selected fuels.
pub const FuelType = enum {
    HFO,
    LFO,
    MDO,
    MGO,
    LPG_propane,
    LPG_butane,
    LNG,
    methanol,
    ethanol,

    /// C_F factor: ratio of CO2 mass produced to fuel mass consumed.
    pub fn carbonFactorKgCO2PerKgFuel(self: FuelType) f64 {
        return switch (self) {
            .HFO => 3.114,
            .LFO => 3.151,
            .MDO => 3.206,
            .MGO => 3.206,
            .LPG_propane => 3.000,
            .LPG_butane => 3.030,
            .LNG => 2.750,
            .methanol => 1.375,
            .ethanol => 1.913,
        };
    }
};

/// Single main-engine or auxiliary-engine entry.
pub const Engine = struct {
    /// Rated mechanical power [kW]. For ME use 75 % MCR; for AE use
    /// the MEPC-defined auxiliary load formula or vendor data.
    P_kw: f64,
    /// Specific fuel consumption [g / kWh] at the certified test cycle.
    SFC_g_per_kwh: f64,
    fuel: FuelType,
};

/// EEDI computation inputs.
pub const EEDIInputs = struct {
    main_engines: []const Engine,
    auxiliary_engines: []const Engine,
    /// Reference deadweight (Capacity) [tonnes].
    capacity_t: f64,
    /// Reference speed at design draft (75 % MCR) [knots].
    V_ref_kt: f64,
    /// Capacity correction factor f_i (>= 1.0). Set 1.0 if no correction.
    f_i: f64,
};

/// Attained EEDI in gCO2 / (t * nm). Numerator units kg CO2 / h
/// then converted via 1000 g/kg and divided by t * nm/h.
pub fn attainedValueGCO2PerTNm(in: EEDIInputs) Error!f64 {
    if (!(in.capacity_t > 0)) return Error.NonPositiveCapacity;
    if (!(in.V_ref_kt > 0)) return Error.NonPositiveSpeed;
    if (!(in.f_i >= 1.0)) return Error.InvalidCorrectionFactor;
    var num: f64 = 0.0;
    for (in.main_engines) |e| {
        if (!(e.P_kw > 0)) return Error.NonPositivePower;
        if (!(e.SFC_g_per_kwh > 0)) return Error.NonPositiveSfc;
        const C_F = e.fuel.carbonFactorKgCO2PerKgFuel();
        num += e.P_kw * (e.SFC_g_per_kwh * 1e-3) * C_F;
    }
    for (in.auxiliary_engines) |e| {
        if (!(e.P_kw > 0)) return Error.NonPositivePower;
        if (!(e.SFC_g_per_kwh > 0)) return Error.NonPositiveSfc;
        const C_F = e.fuel.carbonFactorKgCO2PerKgFuel();
        num += e.P_kw * (e.SFC_g_per_kwh * 1e-3) * C_F;
    }
    // num units: kW * (g / kWh) * 1e-3 (kg/g) * (kg CO2 / kg fuel)
    //          = kg CO2 / hour. Convert to g via * 1e3.
    const denom = in.capacity_t * in.V_ref_kt * in.f_i;
    return num * 1.0e3 / denom;
}

pub const Phase = enum(u8) {
    phase_0 = 0,
    phase_1 = 1,
    phase_2 = 2,
    phase_3 = 3,
};

/// Phase reduction factor X [%] per MEPC.328(76) for bulk carriers
/// of DWT >= 20 000 t in each EEDI phase. Returned as a fraction
/// (e.g. 0.10 for 10 %).
pub fn bulkCarrierReductionFactor(phase: Phase) f64 {
    return switch (phase) {
        .phase_0 => 0.00,
        .phase_1 => 0.10,
        .phase_2 => 0.20,
        .phase_3 => 0.30,
    };
}

/// Required EEDI = baseline * (1 - X). Caller supplies the baseline
/// reference line value from the appropriate ship-type table.
pub fn requiredValueGCO2PerTNm(baseline: f64, phase: Phase) Error!f64 {
    if (!(baseline > 0)) return Error.NonPositiveBaseline;
    const X = bulkCarrierReductionFactor(phase);
    return baseline * (1.0 - X);
}

/// Verdict: attained must be at or below required.
pub const Verdict = enum { pass, fail };

pub fn verdict(attained: f64, required: f64) Verdict {
    if (attained <= required) return .pass;
    return .fail;
}

test "carbon factors match MEPC.337(76) listed values" {
    try std.testing.expectApproxEqAbs(@as(f64, 3.114), FuelType.HFO.carbonFactorKgCO2PerKgFuel(), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 3.206), FuelType.MGO.carbonFactorKgCO2PerKgFuel(), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.750), FuelType.LNG.carbonFactorKgCO2PerKgFuel(), 1e-12);
}

test "attained EEDI: single ME, single AE example" {
    const me = [_]Engine{
        .{ .P_kw = 10_000.0, .SFC_g_per_kwh = 190.0, .fuel = .HFO },
    };
    const ae = [_]Engine{
        .{ .P_kw = 600.0, .SFC_g_per_kwh = 215.0, .fuel = .MGO },
    };
    const in: EEDIInputs = .{
        .main_engines = &me,
        .auxiliary_engines = &ae,
        .capacity_t = 50_000.0,
        .V_ref_kt = 15.0,
        .f_i = 1.0,
    };
    const eedi_val = try attainedValueGCO2PerTNm(in);
    // num kgCO2/h = 10000 * 0.19 * 3.114 + 600 * 0.215 * 3.206
    //             = 5916.6 + 413.574 = 6330.174 kgCO2/h.
    // * 1000 g/kg = 6_330_174 gCO2/h.
    // denom = 50000 t * 15 kt * 1.0 = 750_000 t*kt.
    // eedi = 6330174 / 750000 = 8.44023... g/(t*nm).
    const num = 10000.0 * 0.19 * 3.114 + 600.0 * 0.215 * 3.206;
    const expected = num * 1.0e3 / (50_000.0 * 15.0 * 1.0);
    try std.testing.expectApproxEqAbs(expected, eedi_val, 1e-6);
}

test "EEDI: zero engines yields zero numerator" {
    const me: []const Engine = &[_]Engine{};
    const ae: []const Engine = &[_]Engine{};
    const in: EEDIInputs = .{
        .main_engines = me,
        .auxiliary_engines = ae,
        .capacity_t = 50_000.0,
        .V_ref_kt = 15.0,
        .f_i = 1.0,
    };
    const eedi_val = try attainedValueGCO2PerTNm(in);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), eedi_val, 1e-12);
}

test "EEDI: LNG fuel produces lower value than HFO at the same SFC" {
    const me_hfo = [_]Engine{.{ .P_kw = 10_000.0, .SFC_g_per_kwh = 190.0, .fuel = .HFO }};
    const me_lng = [_]Engine{.{ .P_kw = 10_000.0, .SFC_g_per_kwh = 190.0, .fuel = .LNG }};
    const ae: []const Engine = &[_]Engine{};
    const in_hfo: EEDIInputs = .{
        .main_engines = &me_hfo,
        .auxiliary_engines = ae,
        .capacity_t = 50_000.0,
        .V_ref_kt = 15.0,
        .f_i = 1.0,
    };
    const in_lng: EEDIInputs = .{
        .main_engines = &me_lng,
        .auxiliary_engines = ae,
        .capacity_t = 50_000.0,
        .V_ref_kt = 15.0,
        .f_i = 1.0,
    };
    const v_hfo = try attainedValueGCO2PerTNm(in_hfo);
    const v_lng = try attainedValueGCO2PerTNm(in_lng);
    try std.testing.expect(v_lng < v_hfo);
    try std.testing.expectApproxEqAbs(2.750 / 3.114, v_lng / v_hfo, 1e-6);
}

test "reduction factor monotone increasing with phase" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.00), bulkCarrierReductionFactor(.phase_0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.10), bulkCarrierReductionFactor(.phase_1), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.20), bulkCarrierReductionFactor(.phase_2), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.30), bulkCarrierReductionFactor(.phase_3), 1e-12);
}

test "required EEDI Phase 2: 80% of baseline" {
    const req = try requiredValueGCO2PerTNm(10.0, .phase_2);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), req, 1e-12);
}

test "verdict pass when attained <= required" {
    try std.testing.expectEqual(Verdict.pass, verdict(7.5, 8.0));
    try std.testing.expectEqual(Verdict.pass, verdict(8.0, 8.0));
}

test "verdict fail when attained > required" {
    try std.testing.expectEqual(Verdict.fail, verdict(8.5, 8.0));
}

test "input rejection: non-positive capacity" {
    const me: []const Engine = &[_]Engine{};
    const ae: []const Engine = &[_]Engine{};
    const in: EEDIInputs = .{
        .main_engines = me,
        .auxiliary_engines = ae,
        .capacity_t = 0.0,
        .V_ref_kt = 15.0,
        .f_i = 1.0,
    };
    try std.testing.expectError(Error.NonPositiveCapacity, attainedValueGCO2PerTNm(in));
}

test "input rejection: f_i below 1.0" {
    const me: []const Engine = &[_]Engine{};
    const ae: []const Engine = &[_]Engine{};
    const in: EEDIInputs = .{
        .main_engines = me,
        .auxiliary_engines = ae,
        .capacity_t = 50_000.0,
        .V_ref_kt = 15.0,
        .f_i = 0.9,
    };
    try std.testing.expectError(Error.InvalidCorrectionFactor, attainedValueGCO2PerTNm(in));
}

test "input rejection: non-positive engine power" {
    const me = [_]Engine{.{ .P_kw = 0.0, .SFC_g_per_kwh = 190.0, .fuel = .HFO }};
    const ae: []const Engine = &[_]Engine{};
    const in: EEDIInputs = .{
        .main_engines = &me,
        .auxiliary_engines = ae,
        .capacity_t = 50_000.0,
        .V_ref_kt = 15.0,
        .f_i = 1.0,
    };
    try std.testing.expectError(Error.NonPositivePower, attainedValueGCO2PerTNm(in));
}

test "input rejection: non-positive baseline" {
    try std.testing.expectError(Error.NonPositiveBaseline, requiredValueGCO2PerTNm(0.0, .phase_2));
    try std.testing.expectError(Error.NonPositiveBaseline, requiredValueGCO2PerTNm(-1.5, .phase_2));
}
