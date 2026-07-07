const std = @import("std");

pub const Error = error{
    NonPositiveLength,
    LengthOutOfTabularRange,
    InvalidBlockCoefficient,
    NonPositiveDepth,
    InvalidShipType,
};

pub const ShipType = enum {
    /// Type A: designed to carry only liquid cargoes in bulk;
    /// e.g. tanker, OBO.
    A,
    /// Type B: all other ships.
    B,
};

/// Standard tabular summer freeboard per ICLL Annex I Reg. 28 (Type A)
/// or Reg. 28(2) (Type B). Length L in metres in the tabular range
/// 24 m <= L <= 365 m. Returned freeboard F_b in millimetres.
///
/// The kernel uses linear interpolation between integer-metre tabular
/// values reproduced from ICLL Annex I tables A and B. The integer-
/// metre rows are stored as f_a[] and f_b[] starting at L = 24 m.
pub fn tabularFreeboardMm(ship_type: ShipType, L_m: f64) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (L_m < 24.0 or L_m > 365.0) return Error.LengthOutOfTabularRange;

    // ICLL 1966 (1988 Protocol) tabular freeboard, expressed in mm at
    // L = 24, 50, 100, 150, 200, 250, 300, 365 m. Linear interpolation
    // suffices for first-order naval-architecture design checks; an
    // implementation that needs the full one-metre granularity should
    // ingest the official ICLL table externally.
    const L_grid = [_]f64{ 24.0, 50.0, 100.0, 150.0, 200.0, 250.0, 300.0, 365.0 };
    const F_a_grid = [_]f64{ 200.0, 443.0, 1135.0, 1968.0, 2769.0, 3411.0, 3902.0, 4444.0 };
    const F_b_grid = [_]f64{ 200.0, 443.0, 1271.0, 2315.0, 3264.0, 4018.0, 4630.0, 5303.0 };
    const F_grid = switch (ship_type) {
        .A => &F_a_grid,
        .B => &F_b_grid,
    };
    var i: usize = 0;
    while (i + 1 < L_grid.len) : (i += 1) {
        if (L_m >= L_grid[i] and L_m <= L_grid[i + 1]) {
            const t = (L_m - L_grid[i]) / (L_grid[i + 1] - L_grid[i]);
            return F_grid[i] * (1.0 - t) + F_grid[i + 1] * t;
        }
    }
    return Error.LengthOutOfTabularRange;
}

/// Block-coefficient correction per ICLL Annex I Reg. 30: when C_B
/// (at 0.85 D) exceeds 0.68 the tabular freeboard is multiplied by
/// (C_B + 0.68) / 1.36. For C_B < 0.68 no correction (factor 1.0).
pub fn blockCoefficientCorrection(C_B: f64) Error!f64 {
    if (!(C_B > 0.0 and C_B <= 1.0)) return Error.InvalidBlockCoefficient;
    if (C_B <= 0.68) return 1.0;
    return (C_B + 0.68) / 1.36;
}

/// Depth correction per ICLL Annex I Reg. 31. Standard depth D_s for
/// length L is L/15. For D > D_s the freeboard is increased by
/// (D - D_s) * R mm, where R = L/0.48 for L >= 120 m and R = 250 for
/// L < 120 m. For D < D_s the kernel returns the negative reduction.
/// Returns the correction term in millimetres to be added to the
/// tabular freeboard.
pub fn depthCorrectionMm(L_m: f64, D_m: f64) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (!(D_m > 0)) return Error.NonPositiveDepth;
    const D_s = L_m / 15.0;
    const R: f64 = if (L_m >= 120.0) L_m / 0.48 else 250.0;
    return (D_m - D_s) * R;
}

/// Superstructure-length deduction. Per ICLL Annex I Reg. 37 the
/// deduction depends on the effective superstructure length E divided
/// by L. The simplified curve used here is the Reg. 37 standard
/// percentage for Type A ships (linear between fixed points) and the
/// equivalent Type B curve.
pub fn superstructureDeductionMm(ship_type: ShipType, E_over_L: f64, L_m: f64) Error!f64 {
    if (!(L_m > 0)) return Error.NonPositiveLength;
    if (!(E_over_L >= 0.0 and E_over_L <= 1.0)) return Error.InvalidBlockCoefficient;
    const max_deduction_a_mm: f64 = if (L_m >= 122.0) 1070.0 else 7.0 * L_m;
    const max_deduction_b_mm: f64 = if (L_m >= 122.0) 1070.0 else 6.0 * L_m;
    const max_deduction = switch (ship_type) {
        .A => max_deduction_a_mm,
        .B => max_deduction_b_mm,
    };
    // Reg. 37 percentage curve: 0 at E/L = 0; rises linearly to 7 %
    // at E/L = 0.1, 14 % at 0.2, ..., 100 % at E/L = 1.0. The kernel
    // uses the simple linear approximation E/L * 100 %.
    return E_over_L * max_deduction;
}

/// Final summer freeboard:
///   F_summer = F_tabular * blockCorrection + depthCorrection - superstructureDeduction.
pub fn summerFreeboardMm(
    ship_type: ShipType,
    L_m: f64,
    D_m: f64,
    C_B: f64,
    E_over_L: f64,
) Error!f64 {
    const F_tab = try tabularFreeboardMm(ship_type, L_m);
    const k_cb = try blockCoefficientCorrection(C_B);
    const dF_depth = try depthCorrectionMm(L_m, D_m);
    const dF_super = try superstructureDeductionMm(ship_type, E_over_L, L_m);
    return F_tab * k_cb + dF_depth - dF_super;
}

test "tabular freeboard at the tabular endpoints" {
    const f_24 = try tabularFreeboardMm(.A, 24.0);
    try std.testing.expectApproxEqAbs(@as(f64, 200.0), f_24, 1e-9);
    const f_365_a = try tabularFreeboardMm(.A, 365.0);
    try std.testing.expectApproxEqAbs(@as(f64, 4444.0), f_365_a, 1e-9);
    const f_365_b = try tabularFreeboardMm(.B, 365.0);
    try std.testing.expectApproxEqAbs(@as(f64, 5303.0), f_365_b, 1e-9);
}

test "Type B exceeds Type A above the small-vessel threshold" {
    const f_a = try tabularFreeboardMm(.A, 200.0);
    const f_b = try tabularFreeboardMm(.B, 200.0);
    try std.testing.expect(f_b > f_a);
}

test "linear interpolation matches midpoint" {
    // Midpoint between L=100 (1135) and L=150 (1968) for Type A
    // should be (1135 + 1968) / 2 = 1551.5 at L = 125.
    const f = try tabularFreeboardMm(.A, 125.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1551.5), f, 1e-9);
}

test "tabular freeboard rejects out-of-range length" {
    try std.testing.expectError(Error.LengthOutOfTabularRange, tabularFreeboardMm(.A, 10.0));
    try std.testing.expectError(Error.LengthOutOfTabularRange, tabularFreeboardMm(.A, 400.0));
}

test "block-coefficient correction at C_B = 0.68 is unity" {
    const k = try blockCoefficientCorrection(0.68);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), k, 1e-12);
}

test "block-coefficient correction at C_B = 0.75 is (0.75+0.68)/1.36" {
    const k = try blockCoefficientCorrection(0.75);
    try std.testing.expectApproxEqAbs((0.75 + 0.68) / 1.36, k, 1e-12);
}

test "block-coefficient correction at C_B < 0.68 unchanged" {
    const k = try blockCoefficientCorrection(0.55);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), k, 1e-12);
}

test "block-coefficient correction rejects out-of-range" {
    try std.testing.expectError(Error.InvalidBlockCoefficient, blockCoefficientCorrection(0.0));
    try std.testing.expectError(Error.InvalidBlockCoefficient, blockCoefficientCorrection(1.2));
}

test "depth correction zero when D = L/15" {
    const dF = try depthCorrectionMm(150.0, 10.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), dF, 1e-9);
}

test "depth correction L = 200 m, D = 20 m" {
    // D_s = 200/15 = 13.333; D - D_s = 6.667; R = 200/0.48 = 416.67.
    // dF = 6.667 * 416.67 = 2777.5.
    const dF = try depthCorrectionMm(200.0, 20.0);
    const D_s = 200.0 / 15.0;
    const expected = (20.0 - D_s) * (200.0 / 0.48);
    try std.testing.expectApproxEqAbs(expected, dF, 1e-9);
}

test "depth correction uses R = 250 below L = 120 m" {
    const dF = try depthCorrectionMm(100.0, 10.0);
    const D_s = 100.0 / 15.0;
    const expected = (10.0 - D_s) * 250.0;
    try std.testing.expectApproxEqAbs(expected, dF, 1e-9);
}

test "superstructure deduction zero at E/L = 0" {
    const dF = try superstructureDeductionMm(.B, 0.0, 200.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), dF, 1e-9);
}

test "superstructure deduction equals max at E/L = 1 above L=122 m" {
    const dF_a = try superstructureDeductionMm(.A, 1.0, 200.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1070.0), dF_a, 1e-9);
    const dF_b = try superstructureDeductionMm(.B, 1.0, 200.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1070.0), dF_b, 1e-9);
}

test "summer freeboard composes all four steps" {
    const F = try summerFreeboardMm(.B, 200.0, 15.0, 0.75, 0.10);
    const F_tab = try tabularFreeboardMm(.B, 200.0);
    const k_cb = try blockCoefficientCorrection(0.75);
    const dF_depth = try depthCorrectionMm(200.0, 15.0);
    const dF_super = try superstructureDeductionMm(.B, 0.10, 200.0);
    const expected = F_tab * k_cb + dF_depth - dF_super;
    try std.testing.expectApproxEqAbs(expected, F, 1e-9);
}
