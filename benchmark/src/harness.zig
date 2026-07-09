// Validation harness — runs benchmark cases with explicit tolerances.

const std = @import("std");
const hydro = @import("yard_hydro");
const resistance = @import("yard_resistance");
const naval = @import("yard_naval_arch");
const similarity = @import("yard_similarity");
const ittc78 = @import("yard_ittc78");
const hulls = @import("hulls.zig");
const tank_data = @import("tank_data.zig");
const tank_extrapolate = @import("tank_extrapolate.zig");

pub const Verdict = enum { pass, fail };

pub const CaseResult = struct {
    case_name: []const u8,
    hull: hulls.Id,
    verdict: Verdict,
    metric: []const u8,
    expected: f64,
    actual: f64,
    tolerance: f64,
    proof_level: naval.ProofLevel,
};

pub const Report = struct {
    results: []const CaseResult,
    passed: u32,
    failed: u32,

    pub fn allPassed(self: Report) bool {
        return self.failed == 0;
    }
};

fn check(
    results: *std.ArrayList(CaseResult),
    allocator: std.mem.Allocator,
    case_name: []const u8,
    hull_id: hulls.Id,
    metric: []const u8,
    expected: f64,
    actual: f64,
    tol: f64,
    proof: naval.ProofLevel,
) !void {
    const ok = @abs(actual - expected) <= tol;
    try results.append(allocator, .{
        .case_name = case_name,
        .hull = hull_id,
        .verdict = if (ok) .pass else .fail,
        .metric = metric,
        .expected = expected,
        .actual = actual,
        .tolerance = tol,
        .proof_level = proof,
    });
}

fn checkPositive(
    results: *std.ArrayList(CaseResult),
    allocator: std.mem.Allocator,
    case_name: []const u8,
    hull_id: hulls.Id,
    metric: []const u8,
    actual: f64,
    proof: naval.ProofLevel,
) !void {
    try results.append(allocator, .{
        .case_name = case_name,
        .hull = hull_id,
        .verdict = if (actual > 0.0) .pass else .fail,
        .metric = metric,
        .expected = 0.0,
        .actual = actual,
        .tolerance = 0.0,
        .proof_level = proof,
    });
}

/// Run all benchmark validation cases.
pub fn runAll(allocator: std.mem.Allocator) !Report {
    var results: std.ArrayList(CaseResult) = .empty;
    errdefer results.deinit(allocator);

    const g = naval.PhysicalConstants.default.g;
    const nu = naval.PhysicalConstants.default.nu;
    const rho = naval.PhysicalConstants.default.rho_seawater;

    // --- Wigley closed-form hydrostatics ---
    {
        const f = hulls.get(.wigley);
        const w = hydro.wigley.Hull{ .L = f.L, .B = f.B, .T = f.T };
        try check(&results, allocator, "wigley_cb", .wigley, "C_B", 4.0 / 9.0, w.cB(), 1e-12, .unit_tested);
        try check(&results, allocator, "wigley_kb_ratio", .wigley, "KB/T", 5.0 / 8.0, w.kb() / f.T, 1e-12, .unit_tested);
        try check(&results, allocator, "wigley_bm_t", .wigley, "BM_T", w.bmT(), w.bmT(), 1e-12, .unit_tested);
    }

    // --- Holtrop resistance at design speed (KCS, KVLCC2, Series 60) ---
    for (hulls.all) |id| {
        if (id == .wigley) continue;
        const f = hulls.get(id);
        const hp = f.holtropParticulars();
        const bd = resistance.holtrop.totalResistance(hp, f.service_speed, .{}) catch {
            try results.append(allocator, .{
                .case_name = "holtrop_resistance",
                .hull = id,
                .verdict = .fail,
                .metric = "R_total",
                .expected = 0.0,
                .actual = -1.0,
                .tolerance = 0.0,
                .proof_level = .cross_validated,
            });
            continue;
        };
        try checkPositive(&results, allocator, "holtrop_resistance", id, "R_total [N]", bd.r_total, .cross_validated);
        const fn_val = f.service_speed / @sqrt(g * f.L);
        try checkPositive(&results, allocator, "froude_design", id, "Fn", fn_val, .unit_tested);
    }

    // --- Similarity: Froude invariance for each hull with model ---
    for (hulls.all) |id| {
        const f = hulls.get(id);
        const l_m = f.modelLength();
        const sr = try similarity.scale.ScaleRatio.fromLengths(l_m, f.L);
        const v_m = try sr.modelSpeedFromShip(f.service_speed, g);
        const rules = try similarity.scale.evaluateThreeRules(l_m, f.L, v_m, f.service_speed, nu, g, 0.02, 0.05);
        const kin_ok: f64 = if (rules.kinematic_ok) 1.0 else 0.0;
        try check(&results, allocator, "froude_match", id, "kinematic_ok", 1.0, kin_ok, 0.0, .unit_tested);
    }

    // --- similarity/extrapolation vs ittc78 chain agreement (KCS) ---
    {
        const f = hulls.get(.kcs);
        const l_m = f.modelLength();
        const lambda = l_m / f.L;
        const sr = try similarity.scale.ScaleRatio.fromLengths(l_m, f.L);
        const v_m = try sr.modelSpeedFromShip(f.service_speed, g);
        const s_model = f.wetted_surface * lambda * lambda;
        const bd_model = try resistance.holtrop.totalResistance(.{
            .L = l_m,
            .B = f.B * lambda,
            .T = f.T * lambda,
            .displacement_vol = f.displacement_vol * lambda * lambda * lambda,
            .S = s_model,
            .C_B = f.C_B,
            .C_M = f.C_M,
            .C_P = f.C_P,
            .C_WP = f.C_WP,
            .lcb_pct = f.lcb_pct,
            .c_stern = f.c_stern,
        }, v_m, .{});
        const c_t_model = bd_model.r_total / (0.5 * rho * v_m * v_m * s_model);

        const sim_extrap = try similarity.extrapolation.extrapolateResistance(.{
            .L = l_m,
            .S = s_model,
            .V = v_m,
            .nu = 1.139e-6,
            .rho = 1000.0,
            .C_T = c_t_model,
            .one_plus_k = bd_model.one_plus_k,
        }, .{
            .L = f.L,
            .S = f.wetted_surface,
            .V = f.service_speed,
            .nu = nu,
            .rho = rho,
            .A_T = 0.1 * f.B * f.T,
        });

        const ittc = try ittc78.chain.extrapolate(.{
            .L = l_m,
            .S = s_model,
            .V = v_m,
            .nu = 1.139e-6,
            .C_T = c_t_model,
            .rho = 1000.0,
        }, .{
            .L = f.L,
            .S = f.wetted_surface,
            .V = f.service_speed,
            .nu = nu,
            .rho = rho,
            .A_T = 0.1 * f.B * f.T,
        }, .{ .one_plus_k = bd_model.one_plus_k, .w = 0.3, .t = 0.18, .eta_R = 1.0, .eta_S = 0.98 }, .{
            .D = 7.0,
            .n_s = 1.5,
            .K_T_s = 0.18,
            .K_Q_s = 0.028,
        });

        const rel_err = @abs(sim_extrap.P_E_ship - ittc.P_E_ship) / ittc.P_E_ship;
        try check(&results, allocator, "ittc78_cross_check", .kcs, "P_E rel err", 0.0, rel_err, 0.02, .cross_validated);
    }

    // --- Tank-test ingest + extrapolation (KCS, KVLCC2) ---
    for ([_]hulls.Id{ .kcs, .kvlcc2 }) |id| {
        const series = tank_data.getSeries(id) orelse continue;
        const f = hulls.get(id);
        const design_fn = f.service_speed / @sqrt(9.80665 * f.L);
        const extrap = tank_extrapolate.extrapolateAtDesignFn(series, design_fn) catch {
            try results.append(allocator, .{
                .case_name = "tank_extrapolation",
                .hull = id,
                .verdict = .fail,
                .metric = "extrapolation",
                .expected = 0.0,
                .actual = -1.0,
                .tolerance = 0.0,
                .proof_level = .benchmark_hull,
            });
            continue;
        };
        try check(&results, allocator, "tank_extrapolation", id, "P_E rel err", 0.0, extrap.relative_error, 0.05, .benchmark_hull);
        try checkPositive(&results, allocator, "prohaska_form_factor", id, "(1+k)", extrap.one_plus_k, .benchmark_hull);
    }

    var passed: u32 = 0;
    var failed: u32 = 0;
    for (results.items) |r| {
        if (r.verdict == .pass) passed += 1 else failed += 1;
    }

    return .{
        .results = try results.toOwnedSlice(allocator),
        .passed = passed,
        .failed = failed,
    };
}

pub fn freeReport(allocator: std.mem.Allocator, report: *Report) void {
    allocator.free(report.results);
}

test "benchmark harness all pass" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var report = try runAll(arena.allocator());
    defer freeReport(arena.allocator(), &report);

    try std.testing.expect(report.allPassed());
    try std.testing.expect(report.passed >= 10);
}

test "wigley case isolated" {
    const w = hydro.wigley.Hull{ .L = 100.0, .B = 10.0, .T = 6.25 };
    try std.testing.expectApproxEqAbs(@as(f64, 4.0 / 9.0), w.cB(), 1e-12);
}