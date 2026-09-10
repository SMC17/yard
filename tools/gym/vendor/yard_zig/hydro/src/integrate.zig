// Hydrostatic integrators consuming precomputed ordinate arrays.
//
// Inputs are ordinate tables produced from a hull's geometry (analytical or
// from an offsets table). All integration is Simpson 1/3, so the ordinate
// count must be odd (>= 3) and station spacing dx > 0.
//
// The tests in this module cross-check that integrating analytical Wigley
// and box-barge ordinates reproduces the closed-form hydrostatic quantities.

const std = @import("std");
const simpson = @import("simpson.zig");
const wigley = @import("wigley.zig");
const box_barge = @import("box_barge.zig");

/// Volume of displacement integrated as int A(x) dx using Simpson 1/3.
/// sectional_areas: A(x_i) at i = 0..n-1 (n odd).
/// dx: longitudinal station spacing.
pub fn volumeFromAreas(sectional_areas: []const f64, dx: f64) simpson.Error!f64 {
    return simpson.simpson13(sectional_areas, dx);
}

/// Waterplane area integrated as int 2 y(x, T_design) dx using Simpson 1/3.
/// half_breadths: y(x_i, T_design) at i = 0..n-1.
pub fn waterplaneAreaFromHalfBreadths(half_breadths: []const f64, dx: f64) simpson.Error!f64 {
    // Caller passes half-breadths; we integrate 2 * y over x.
    // To avoid allocation, multiply Simpson result by 2.
    const half_integral = try simpson.simpson13(half_breadths, dx);
    return 2.0 * half_integral;
}

/// Transverse moment of inertia of waterplane.
/// I_T = int (2/3) y(x, T_design)^3 dx = (2/3) int y^3 dx.
/// (Standard naval-architecture formula; rotation axis is the centerline.)
pub fn iTFromHalfBreadths(half_breadths: []const f64, dx: f64, scratch: []f64) simpson.Error!f64 {
    if (scratch.len != half_breadths.len) return simpson.Error.InvalidOrdinateCount;
    var i: usize = 0;
    while (i < half_breadths.len) : (i += 1) {
        const y = half_breadths[i];
        scratch[i] = y * y * y;
    }
    const cube_integral = try simpson.simpson13(scratch, dx);
    return (2.0 / 3.0) * cube_integral;
}

/// Longitudinal center of buoyancy from amidships.
/// LCB = (1/V) int x * A(x) dx, with x measured from amidships.
/// stations: A(x_i); x_start: position of station 0 (negative for midship-centered grid).
pub fn lcbFromAreas(
    sectional_areas: []const f64,
    dx: f64,
    x_start: f64,
    scratch: []f64,
) simpson.Error!f64 {
    if (scratch.len != sectional_areas.len) return simpson.Error.InvalidOrdinateCount;
    var i: usize = 0;
    while (i < sectional_areas.len) : (i += 1) {
        const x = x_start + @as(f64, @floatFromInt(i)) * dx;
        scratch[i] = x * sectional_areas[i];
    }
    const moment = try simpson.simpson13(scratch, dx);
    const volume = try simpson.simpson13(sectional_areas, dx);
    return moment / volume;
}

const expectApproxEqRel = std.testing.expectApproxEqRel;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "Wigley volume integration matches closed form exactly" {
    // Wigley sectional-area integrand is a degree-2 polynomial in x.
    // Simpson 1/3 is exact for polynomials of degree <= 3.
    const h = wigley.Hull{ .L = 2.5, .B = 0.25, .T = 0.15625 };
    var areas: [21]f64 = undefined;
    h.sectionalAreas(&areas);
    const dx = h.L / 20.0;
    const v = try volumeFromAreas(&areas, dx);
    try expectApproxEqRel(h.volume(), v, 1e-14);
}

test "Wigley waterplane area integration matches closed form exactly" {
    const h = wigley.Hull{ .L = 100.0, .B = 10.0, .T = 4.0 };
    var half_breadths: [21]f64 = undefined;
    h.waterlineOrdinates(0.0, &half_breadths);
    const dx = h.L / 20.0;
    const a_w = try waterplaneAreaFromHalfBreadths(&half_breadths, dx);
    try expectApproxEqRel(h.waterplaneArea(), a_w, 1e-14);
}

test "Wigley LCB is exactly zero by symmetry" {
    const h = wigley.Hull{ .L = 100.0, .B = 10.0, .T = 4.0 };
    var areas: [21]f64 = undefined;
    h.sectionalAreas(&areas);
    const dx = h.L / 20.0;
    var scratch: [21]f64 = undefined;
    const lcb = try lcbFromAreas(&areas, dx, -0.5 * h.L, &scratch);
    try expectApproxEqAbs(@as(f64, 0.0), lcb, 1e-12);
}

test "Wigley I_T integration converges to closed form as N grows" {
    // I_T integrand is degree-6 polynomial in x. Simpson 1/3 is not exact;
    // error scales as h^4. Check that 81-station integration is within
    // tight tolerance of the closed form.
    const h = wigley.Hull{ .L = 100.0, .B = 10.0, .T = 4.0 };
    const N: usize = 81;
    var half_breadths: [N]f64 = undefined;
    h.waterlineOrdinates(0.0, &half_breadths);
    const dx = h.L / @as(f64, @floatFromInt(N - 1));
    var scratch: [N]f64 = undefined;
    const i_t_numeric = try iTFromHalfBreadths(&half_breadths, dx, &scratch);
    try expectApproxEqRel(h.iT(), i_t_numeric, 1e-5);
}

test "Wigley I_T integration converges with O(h^4) order" {
    // Halving h should reduce the error by factor 16 (fourth order).
    const h = wigley.Hull{ .L = 100.0, .B = 10.0, .T = 4.0 };
    const truth = h.iT();

    var ords21: [21]f64 = undefined;
    var sc21: [21]f64 = undefined;
    h.waterlineOrdinates(0.0, &ords21);
    const i_t_21 = try iTFromHalfBreadths(&ords21, h.L / 20.0, &sc21);
    const err_21 = @abs(i_t_21 - truth) / truth;

    var ords41: [41]f64 = undefined;
    var sc41: [41]f64 = undefined;
    h.waterlineOrdinates(0.0, &ords41);
    const i_t_41 = try iTFromHalfBreadths(&ords41, h.L / 40.0, &sc41);
    const err_41 = @abs(i_t_41 - truth) / truth;

    // 4th-order convergence: ratio of errors should be near 2^4 = 16.
    // Allow slack: ratio >= 8 (between O(h^3) and O(h^4)) is acceptance.
    const ratio = err_21 / err_41;
    try std.testing.expect(ratio >= 8.0);
}

test "box-barge volume integration matches L B T exactly" {
    const b = box_barge.Barge{ .L = 10.0, .B = 4.0, .T = 1.5 };
    var areas: [5]f64 = undefined;
    b.sectionalAreas(&areas);
    const dx = b.L / 4.0;
    const v = try volumeFromAreas(&areas, dx);
    try expectApproxEqRel(b.volume(), v, 1e-14);
}

test "box-barge waterplane area integration matches L B exactly" {
    const b = box_barge.Barge{ .L = 10.0, .B = 4.0, .T = 1.5 };
    var half_breadths: [5]f64 = undefined;
    b.waterlineOrdinates(&half_breadths);
    const dx = b.L / 4.0;
    const a_w = try waterplaneAreaFromHalfBreadths(&half_breadths, dx);
    try expectApproxEqRel(b.waterplaneArea(), a_w, 1e-14);
}

test "box-barge I_T integration matches L B^3 / 12 exactly" {
    const b = box_barge.Barge{ .L = 10.0, .B = 4.0, .T = 1.5 };
    var half_breadths: [5]f64 = undefined;
    var scratch: [5]f64 = undefined;
    b.waterlineOrdinates(&half_breadths);
    const dx = b.L / 4.0;
    const i_t = try iTFromHalfBreadths(&half_breadths, dx, &scratch);
    try expectApproxEqRel(b.iT(), i_t, 1e-14);
}
