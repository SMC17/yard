const std = @import("std");

pub const Error = error{
    UnequalLength,
    InsufficientPoints,
    NonPositiveCF,
    DegenerateData,
};

/// Result of a Prohaska linear regression.
pub const Result = struct {
    /// Form factor (1 + k) inferred as the intercept of the linear fit.
    one_plus_k: f64,
    /// Wave-resistance slope coefficient `a` in C_W ~ a Fn^4.
    slope_a: f64,
    /// Coefficient of determination R^2 of the linear fit.
    r_squared: f64,
};

/// Run a Prohaska linear regression. Inputs are sample arrays of
/// Froude number, total-resistance coefficient C_T, and frictional
/// coefficient C_F (typically ITTC-57). All three slices must have
/// equal length and at least three points.
pub fn fit(Fn_array: []const f64, CT_array: []const f64, CF_array: []const f64) Error!Result {
    if (Fn_array.len != CT_array.len) return Error.UnequalLength;
    if (Fn_array.len != CF_array.len) return Error.UnequalLength;
    if (Fn_array.len < 3) return Error.InsufficientPoints;
    var sum_x: f64 = 0;
    var sum_y: f64 = 0;
    var sum_xx: f64 = 0;
    var sum_xy: f64 = 0;
    var sum_yy: f64 = 0;
    const n_f: f64 = @floatFromInt(Fn_array.len);
    var i: usize = 0;
    while (i < Fn_array.len) : (i += 1) {
        if (!(CF_array[i] > 0)) return Error.NonPositiveCF;
        const fn_p4 = Fn_array[i] * Fn_array[i] * Fn_array[i] * Fn_array[i];
        const x = fn_p4 / CF_array[i];
        const y = CT_array[i] / CF_array[i];
        sum_x += x;
        sum_y += y;
        sum_xx += x * x;
        sum_xy += x * y;
        sum_yy += y * y;
    }
    const denom = n_f * sum_xx - sum_x * sum_x;
    if (@abs(denom) < 1e-30) return Error.DegenerateData;
    const slope = (n_f * sum_xy - sum_x * sum_y) / denom;
    const intercept = (sum_y - slope * sum_x) / n_f;
    // R^2 = 1 - SS_res / SS_tot.
    const y_bar = sum_y / n_f;
    const ss_tot = sum_yy - n_f * y_bar * y_bar;
    var ss_res: f64 = 0.0;
    i = 0;
    while (i < Fn_array.len) : (i += 1) {
        const fn_p4 = Fn_array[i] * Fn_array[i] * Fn_array[i] * Fn_array[i];
        const x = fn_p4 / CF_array[i];
        const y = CT_array[i] / CF_array[i];
        const y_pred = intercept + slope * x;
        const r = y - y_pred;
        ss_res += r * r;
    }
    const r_squared: f64 = if (ss_tot > 0) 1.0 - ss_res / ss_tot else 1.0;
    return .{
        .one_plus_k = intercept,
        .slope_a = slope,
        .r_squared = r_squared,
    };
}

test "Prohaska on perfect synthetic data recovers (1+k) and slope" {
    // Build synthetic (Fn, C_T, C_F) with known one_plus_k = 1.15,
    // slope_a = 0.5, and a typical ITTC-57 C_F at Rn = 1e7 ~ 0.003.
    const one_plus_k_truth: f64 = 1.15;
    const a_truth: f64 = 0.5;
    var Fn_arr: [9]f64 = undefined;
    var CT_arr: [9]f64 = undefined;
    var CF_arr: [9]f64 = undefined;
    var i: usize = 0;
    while (i < Fn_arr.len) : (i += 1) {
        Fn_arr[i] = 0.10 + 0.01 * @as(f64, @floatFromInt(i));
        CF_arr[i] = 0.003;
        // C_T = (1+k) C_F + a Fn^4
        const fn4 = Fn_arr[i] * Fn_arr[i] * Fn_arr[i] * Fn_arr[i];
        CT_arr[i] = one_plus_k_truth * CF_arr[i] + a_truth * fn4;
    }
    const r = try fit(&Fn_arr, &CT_arr, &CF_arr);
    try std.testing.expectApproxEqAbs(one_plus_k_truth, r.one_plus_k, 1e-9);
    try std.testing.expectApproxEqAbs(a_truth, r.slope_a, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), r.r_squared, 1e-9);
}

test "Prohaska tolerates mild noise (R^2 above 0.99)" {
    const one_plus_k_truth: f64 = 1.20;
    const a_truth: f64 = 0.8;
    var Fn_arr: [15]f64 = undefined;
    var CT_arr: [15]f64 = undefined;
    var CF_arr: [15]f64 = undefined;
    // Reproducible deterministic perturbation.
    var i: usize = 0;
    while (i < Fn_arr.len) : (i += 1) {
        Fn_arr[i] = 0.10 + 0.01 * @as(f64, @floatFromInt(i));
        CF_arr[i] = 0.003;
        const fn4 = Fn_arr[i] * Fn_arr[i] * Fn_arr[i] * Fn_arr[i];
        const base = one_plus_k_truth * CF_arr[i] + a_truth * fn4;
        const noise = 1.0e-6 * @sin(@as(f64, @floatFromInt(i)) * 0.7);
        CT_arr[i] = base + noise;
    }
    const r = try fit(&Fn_arr, &CT_arr, &CF_arr);
    try std.testing.expect(r.r_squared > 0.99);
    try std.testing.expect(@abs(r.one_plus_k - one_plus_k_truth) < 1e-2);
    try std.testing.expect(@abs(r.slope_a - a_truth) < 0.5);
}

test "Prohaska rejects unequal-length inputs" {
    const Fn_arr: [3]f64 = .{ 0.1, 0.2, 0.3 };
    const CT_arr: [3]f64 = .{ 1, 2, 3 };
    const CF_arr: [2]f64 = .{ 1, 2 };
    try std.testing.expectError(Error.UnequalLength, fit(&Fn_arr, &CT_arr, &CF_arr));
}

test "Prohaska rejects fewer than three points" {
    const Fn_arr: [2]f64 = .{ 0.1, 0.2 };
    const CT_arr: [2]f64 = .{ 1, 2 };
    const CF_arr: [2]f64 = .{ 1, 1 };
    try std.testing.expectError(Error.InsufficientPoints, fit(&Fn_arr, &CT_arr, &CF_arr));
}

test "Prohaska rejects non-positive C_F" {
    const Fn_arr: [3]f64 = .{ 0.1, 0.2, 0.3 };
    const CT_arr: [3]f64 = .{ 1, 2, 3 };
    const CF_arr: [3]f64 = .{ 1, 0.0, 1 };
    try std.testing.expectError(Error.NonPositiveCF, fit(&Fn_arr, &CT_arr, &CF_arr));
}

test "Prohaska detects degenerate (zero-variance) X data" {
    // Constant Fn means constant Fn^4 / C_F. SS_xx = 0 -> degenerate.
    const Fn_arr: [4]f64 = .{ 0.1, 0.1, 0.1, 0.1 };
    const CT_arr: [4]f64 = .{ 1, 2, 3, 4 };
    const CF_arr: [4]f64 = .{ 1, 1, 1, 1 };
    try std.testing.expectError(Error.DegenerateData, fit(&Fn_arr, &CT_arr, &CF_arr));
}

test "Prohaska zero slope corresponds to a purely viscous regime" {
    // Build data with a_truth = 0 -> C_T = (1+k) C_F at every Fn.
    var Fn_arr: [6]f64 = undefined;
    var CT_arr: [6]f64 = undefined;
    var CF_arr: [6]f64 = undefined;
    const one_plus_k_truth: f64 = 1.30;
    var i: usize = 0;
    while (i < Fn_arr.len) : (i += 1) {
        Fn_arr[i] = 0.08 + 0.01 * @as(f64, @floatFromInt(i));
        CF_arr[i] = 0.003;
        CT_arr[i] = one_plus_k_truth * CF_arr[i];
    }
    const r = try fit(&Fn_arr, &CT_arr, &CF_arr);
    try std.testing.expectApproxEqAbs(one_plus_k_truth, r.one_plus_k, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), r.slope_a, 1e-9);
}

test "Prohaska intercept recovers when Fn = 0 is included" {
    // Including Fn = 0 fixes the intercept at exactly C_T / C_F.
    const one_plus_k_truth: f64 = 1.10;
    const a_truth: f64 = 0.6;
    const CF: f64 = 0.0035;
    const Fn_arr = [_]f64{ 0.0, 0.08, 0.10, 0.12, 0.14, 0.16 };
    var CT_arr: [Fn_arr.len]f64 = undefined;
    var CF_arr: [Fn_arr.len]f64 = undefined;
    var i: usize = 0;
    while (i < Fn_arr.len) : (i += 1) {
        CF_arr[i] = CF;
        const fn4 = Fn_arr[i] * Fn_arr[i] * Fn_arr[i] * Fn_arr[i];
        CT_arr[i] = one_plus_k_truth * CF + a_truth * fn4;
    }
    const r = try fit(&Fn_arr, &CT_arr, &CF_arr);
    try std.testing.expectApproxEqAbs(one_plus_k_truth, r.one_plus_k, 1e-9);
    try std.testing.expectApproxEqAbs(a_truth, r.slope_a, 1e-9);
}
