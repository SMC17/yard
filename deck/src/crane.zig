const std = @import("std");

pub const Error = error{
    NonPositiveLoad,
    NonPositiveOutreach,
    OutreachOutOfRange,
    InvalidChartLength,
};

/// Crane heeling moment about the slewing centre:
///   M = SWL * g * r
/// Returns Nm with SWL in tonnes, g in m/s^2, r in m.
pub fn heelingMomentNm(SWL_t: f64, outreach_m: f64, g_mps2: f64) Error!f64 {
    if (!(SWL_t > 0)) return Error.NonPositiveLoad;
    if (!(outreach_m > 0)) return Error.NonPositiveOutreach;
    return SWL_t * g_mps2 * outreach_m * 1000.0;
}

/// Linear interpolation of an SWL vs outreach load chart. The chart
/// is a monotonically descending step list of (r_i, SWL_i) anchor
/// points. Linear interp between adjacent points; clamped at the
/// endpoints.
pub fn swlFromChart(
    outreach_arr: []const f64,
    swl_arr: []const f64,
    r_m: f64,
) Error!f64 {
    if (outreach_arr.len != swl_arr.len) return Error.InvalidChartLength;
    if (outreach_arr.len < 2) return Error.InvalidChartLength;
    if (!(r_m > 0)) return Error.NonPositiveOutreach;
    if (r_m < outreach_arr[0]) return swl_arr[0];
    if (r_m >= outreach_arr[outreach_arr.len - 1]) return swl_arr[swl_arr.len - 1];
    var i: usize = 0;
    while (i + 1 < outreach_arr.len) : (i += 1) {
        if (r_m >= outreach_arr[i] and r_m <= outreach_arr[i + 1]) {
            const t = (r_m - outreach_arr[i]) /
                (outreach_arr[i + 1] - outreach_arr[i]);
            return swl_arr[i] * (1.0 - t) + swl_arr[i + 1] * t;
        }
    }
    return Error.OutreachOutOfRange;
}

/// Hyperbolic-tip moment-limit chart: SWL(r) = M_max / (g r), so
/// that the slewing-centre moment SWL g r equals a constant M_max.
pub fn swlMomentLimit(M_max_nm: f64, r_m: f64, g_mps2: f64) Error!f64 {
    if (!(M_max_nm > 0)) return Error.NonPositiveLoad;
    if (!(r_m > 0)) return Error.NonPositiveOutreach;
    return M_max_nm / (g_mps2 * r_m * 1000.0);
}

test "heeling moment at SWL = 50 t, r = 20 m, g = 9.81" {
    const M = try heelingMomentNm(50.0, 20.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0 * 9.81 * 20.0 * 1000.0), M, 1e-6);
}

test "heeling moment scales linearly with SWL and r" {
    const M_base = try heelingMomentNm(50.0, 20.0, 9.81);
    const M_swl = try heelingMomentNm(100.0, 20.0, 9.81);
    const M_r = try heelingMomentNm(50.0, 40.0, 9.81);
    try std.testing.expectApproxEqAbs(2.0 * M_base, M_swl, 1e-6);
    try std.testing.expectApproxEqAbs(2.0 * M_base, M_r, 1e-6);
}

test "SWL chart interpolation: r between anchor points" {
    const r = [_]f64{ 10.0, 20.0, 30.0 };
    const swl = [_]f64{ 100.0, 50.0, 25.0 };
    const v = try swlFromChart(&r, &swl, 15.0);
    // Midpoint between 100 and 50 = 75.
    try std.testing.expectApproxEqAbs(@as(f64, 75.0), v, 1e-9);
}

test "SWL chart at exact anchor point" {
    const r = [_]f64{ 10.0, 20.0, 30.0 };
    const swl = [_]f64{ 100.0, 50.0, 25.0 };
    const v = try swlFromChart(&r, &swl, 20.0);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), v, 1e-9);
}

test "SWL chart below first anchor clamps to first SWL" {
    const r = [_]f64{ 10.0, 20.0, 30.0 };
    const swl = [_]f64{ 100.0, 50.0, 25.0 };
    const v = try swlFromChart(&r, &swl, 5.0);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), v, 1e-9);
}

test "SWL chart above last anchor clamps to last SWL" {
    const r = [_]f64{ 10.0, 20.0, 30.0 };
    const swl = [_]f64{ 100.0, 50.0, 25.0 };
    const v = try swlFromChart(&r, &swl, 50.0);
    try std.testing.expectApproxEqAbs(@as(f64, 25.0), v, 1e-9);
}

test "moment-limit chart: SWL r = constant" {
    // M_max = 10 MNm. At r=10: SWL = 10e6 / (9.81 * 10 * 1000) = 101.94 t.
    const swl_10 = try swlMomentLimit(10.0e6, 10.0, 9.81);
    const swl_20 = try swlMomentLimit(10.0e6, 20.0, 9.81);
    try std.testing.expectApproxEqAbs(2.0 * swl_20, swl_10, 1e-6);
}

test "moment-limit chart at r = 10, M_max = 9.81 GNm reduces to 100 000 t" {
    const swl = try swlMomentLimit(9.81e9, 10.0, 9.81);
    try std.testing.expectApproxEqAbs(@as(f64, 100_000.0), swl, 1e-3);
}

test "input rejection: zero SWL" {
    try std.testing.expectError(Error.NonPositiveLoad, heelingMomentNm(0.0, 20.0, 9.81));
}

test "input rejection: zero outreach" {
    try std.testing.expectError(Error.NonPositiveOutreach, heelingMomentNm(50.0, 0.0, 9.81));
}

test "input rejection: chart unequal lengths" {
    const r = [_]f64{ 10.0, 20.0 };
    const swl = [_]f64{100.0};
    try std.testing.expectError(Error.InvalidChartLength, swlFromChart(&r, &swl, 15.0));
}

test "input rejection: chart too short" {
    const r = [_]f64{10.0};
    const swl = [_]f64{100.0};
    try std.testing.expectError(Error.InvalidChartLength, swlFromChart(&r, &swl, 15.0));
}
