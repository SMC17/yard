//! End-to-end box-barge intact stability workflow.
//! Wires hydro/box_barge → stability/gz → stability/is_code.

const std = @import("std");
const hydro = @import("yard_hydro");
const stability = @import("yard_stability");
const naval = @import("yard_naval_arch");

pub const Error = error{
    IsCodeEvaluationFailed,
    OutOfMemory,
};

pub const Input = struct {
    particulars: naval.PrincipalParticulars,
    loading: naval.LoadingCondition,
    constants: naval.PhysicalConstants = .default,
    /// Maximum heel for wall-sided GZ curve [deg]. Default 40.
    max_heel_deg: f64 = 40.0,
    /// GZ curve step [deg]. Default 5.
    heel_step_deg: f64 = 5.0,
};

pub const Output = struct {
    hydrostatics: naval.Hydrostatics,
    stability: naval.StabilitySummary,
    gz_curve: []const naval.GzSample,
    is_code: naval.IsCodeResult,
    flags: naval.ValidityFlags,
    proof_level: naval.ProofLevel = .unit_tested,
};

/// Run the canonical box-barge intact stability + IS Code 2.2 workflow.
pub fn evaluate(allocator: std.mem.Allocator, input: Input) Error!Output {
    const p = input.particulars;
    const barge = hydro.box_barge.Barge{ .L = p.L, .B = p.B, .T = p.T };

    const V = barge.volume();
    const disp = V * input.constants.rho_seawater;
    const kb = barge.kb();
    const bm_t = barge.bmT();
    const km_t = barge.kmT();

    const gm0 = km_t - input.loading.kg_m;

    // Free-surface correction.
    var tanks = try allocator.alloc(stability.gz.Tank, input.loading.tanks.len);
    defer allocator.free(tanks);
    for (input.loading.tanks, 0..) |t, i| {
        tanks[i] = .{
            .rho_fluid = t.rho_fluid,
            .i_fs = stability.gz.rectTankIfs(t.l_m, t.b_m),
        };
    }
    const gm_corrected = stability.gz.effectiveGM(gm0, tanks, input.constants.rho_seawater, V);

    // Wall-sided validity: B/(2T) > 1 (Biran deck-edge criterion for box forms).
    const wall_sided_valid = (p.B / (2.0 * p.T)) > 1.0;

    var flags: naval.ValidityFlags = .{};
    if (wall_sided_valid) flags.insert(.wall_sided_assumption_valid);
    if (input.loading.tanks.len > 0) flags.insert(.free_surface_applied);
    if (input.max_heel_deg <= 10.0) flags.insert(.small_angle_regime);

    const gzAt = struct {
        fn compute(gm: f64, bm: f64, rad: f64, wall_sided: bool) f64 {
            return if (wall_sided)
                stability.gz.wallSidedGZ(gm, bm, rad)
            else
                stability.gz.smallAngleGZ(gm, rad);
        }
    }.compute;

    // Display GZ curve (user-controlled range).
    const n_curve = @as(usize, @intFromFloat(@floor(input.max_heel_deg / input.heel_step_deg))) + 1;
    var gz_curve = try allocator.alloc(naval.GzSample, n_curve);
    errdefer allocator.free(gz_curve);
    {
        var i: usize = 0;
        var deg: f64 = 0.0;
        while (i < n_curve) : (i += 1) {
            const rad = naval.units.degToRad(deg);
            const gz_m = gzAt(gm_corrected, bm_t, rad, wall_sided_valid);
            gz_curve[i] = .{ .angle_deg = deg, .angle_rad = rad, .gz_m = gz_m };
            deg += input.heel_step_deg;
        }
    }

    // IS Code requires samples through 40° (minimum 3 points).
    const is_heel_step: f64 = 5.0;
    const n_is = @as(usize, @intFromFloat(@floor(40.0 / is_heel_step))) + 1;
    var is_angles = try allocator.alloc(f64, n_is);
    defer allocator.free(is_angles);
    var is_gz = try allocator.alloc(f64, n_is);
    defer allocator.free(is_gz);
    {
        var i: usize = 0;
        var deg: f64 = 0.0;
        while (i < n_is) : (i += 1) {
            const rad = naval.units.degToRad(deg);
            is_angles[i] = rad;
            is_gz[i] = gzAt(gm_corrected, bm_t, rad, wall_sided_valid);
            deg += is_heel_step;
        }
    }

    const is_raw = stability.is_code.evaluate(is_angles, is_gz, gm0) catch return Error.IsCodeEvaluationFailed;

    const is_result: naval.IsCodeResult = .{
        .area_0_30 = mapVerdict(is_raw.area_0_30),
        .area_0_40 = mapVerdict(is_raw.area_0_40),
        .area_30_40 = mapVerdict(is_raw.area_30_40),
        .gz_at_30 = mapVerdict(is_raw.gz_at_30),
        .angle_gz_max = mapVerdict(is_raw.angle_gz_max),
        .gm_0 = mapVerdict(is_raw.gm_0),
        .overall = mapVerdict(is_raw.overall),
        .values = .{
            .area_0_30 = is_raw.values.area_0_30,
            .area_0_40 = is_raw.values.area_0_40,
            .area_30_40 = is_raw.values.area_30_40,
            .gz_at_30 = is_raw.values.gz_at_30,
            .angle_gz_max_deg = is_raw.values.angle_gz_max_deg,
            .gm_0 = is_raw.values.gm_0,
        },
    };

    return .{
        .hydrostatics = .{
            .volume_m3 = V,
            .displacement_kg = disp,
            .kb_m = kb,
            .bm_t_m = bm_t,
            .km_t_m = km_t,
            .lcb_m = barge.lcb(),
            .c_b = barge.cB(),
        },
        .stability = .{
            .gm0_m = gm0,
            .gm_corrected_m = gm_corrected,
            .gg_prime_m = gm0 - gm_corrected, // GG' = GM₀ − GM_corrected
            .wall_sided_valid = wall_sided_valid,
        },
        .gz_curve = gz_curve,
        .is_code = is_result,
        .flags = flags,
    };
}

fn mapVerdict(v: stability.is_code.Verdict) naval.types.CriterionVerdict {
    return switch (v) {
        .pass => .pass,
        .fail => .fail,
    };
}

const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "canonical box-barge matches validation_fixtures" {
    const input: Input = .{
        .particulars = .{ .L = 10.0, .B = 4.0, .T = 1.5 },
        .loading = .{
            .kg_m = 1.0,
            .tanks = &[_]naval.TankSpec{
                .{ .l_m = 5.0, .b_m = 3.0, .rho_fluid = 1000.0 },
            },
        },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const out = try evaluate(allocator, input);

    // Biran 2013 Ch.10: GM = 0.6389, KM_T = 1.6389
    try expectApproxEqAbs(@as(f64, 0.6389), out.stability.gm0_m, 1e-3);
    try expectApproxEqAbs(@as(f64, 1.6389), out.hydrostatics.km_t_m, 1e-3);

    // Free-surface: GG' ~ 0.183 m → GM_eff ~ 0.456 m
    try expectApproxEqAbs(@as(f64, 0.183), out.stability.gg_prime_m, 1e-2);
    try expectApproxEqAbs(@as(f64, 0.456), out.stability.gm_corrected_m, 1e-2);

    try std.testing.expect(out.flags.contains(.free_surface_applied));
    try std.testing.expect(out.flags.contains(.wall_sided_assumption_valid));
}

test "wall-sided GZ at 10 deg matches fixture" {
    const input: Input = .{
        .particulars = .{ .L = 10.0, .B = 4.0, .T = 1.5 },
        .loading = .{ .kg_m = 1.0, .tanks = &.{} },
        .max_heel_deg = 10.0,
        .heel_step_deg = 10.0,
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try evaluate(arena.allocator(), input);

    // validation_fixtures: GZ at 10 deg ~ 0.1134 m (uncorrected GM)
    try expectApproxEqAbs(@as(f64, 0.1134), out.gz_curve[1].gz_m, 1e-3);
}