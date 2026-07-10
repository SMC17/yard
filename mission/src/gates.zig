//! Validity gates: a submission must pass every gate before it is scored.
//! Gate failures return a physically-grounded reason, never a score —
//! degenerate designs are rejected, not ranked.

const std = @import("std");
const naval = @import("yard_naval_arch");
const box_barge = @import("yard_box_barge");
const cargo_resistance = @import("yard_cargo_resistance");
const spec = @import("spec.zig");

pub const Error = error{OutOfMemory};

pub const Check = struct {
    pass: bool,
    /// Measured value the gate compared.
    value: f64,
    /// Limit the value was compared against.
    limit: f64,
};

pub const Report = struct {
    era_envelope: Check,
    freeboard: Check,
    intact_stability: Check,
    is_code_overall: Check,
    resistance_envelope: Check,
    all_pass: bool,
    /// Free-surface-corrected GM from the stability workflow [m].
    gm_corrected_m: f64,
};

/// Hull proxy note: v0 evaluates stability on the box-barge workflow with the
/// submission's B and T (canonical yard intact-stability path). Hull-form GZ
/// via the panel modules replaces this in a later rung.
pub fn evaluate(allocator: std.mem.Allocator, mission: spec.MissionSpec, sub: spec.Submission) Error!Report {
    const h = sub.hull;

    // Era envelope: dimensional caps + L/D strength proxy.
    const l_over_d = h.loa_m / h.depth_m;
    const era_ok = h.loa_m <= mission.era.max_loa_m and
        h.beam_m <= mission.era.max_beam_m and
        h.draft_m <= mission.era.max_draft_m and
        l_over_d <= mission.era.max_l_over_d;
    const era_check: Check = .{ .pass = era_ok, .value = l_over_d, .limit = mission.era.max_l_over_d };

    // Freeboard: load-line proxy on depth.
    const freeboard = h.depth_m - h.draft_m;
    const freeboard_min = mission.era.min_freeboard_frac * h.depth_m;
    const freeboard_check: Check = .{
        .pass = freeboard >= freeboard_min and freeboard > 0,
        .value = freeboard,
        .limit = freeboard_min,
    };

    // Intact stability via the canonical box-barge workflow.
    var tanks = try allocator.alloc(naval.TankSpec, sub.loading.tanks.len);
    defer allocator.free(tanks);
    for (sub.loading.tanks, 0..) |t, i| {
        tanks[i] = .{ .l_m = t.l_m, .b_m = t.b_m, .rho_fluid = t.rho_fluid };
    }

    var gm_corrected: f64 = 0;
    var gm_check: Check = .{ .pass = false, .value = 0, .limit = mission.gates.min_gm_m };
    var is_code_check: Check = .{ .pass = false, .value = 0, .limit = 1 };
    const stab: ?box_barge.Output = box_barge.evaluate(allocator, .{
        .particulars = .{ .L = h.loa_m, .B = h.beam_m, .T = h.draft_m },
        .loading = .{ .kg_m = sub.loading.kg_m, .tanks = tanks },
    }) catch |err| switch (err) {
        error.OutOfMemory => return Error.OutOfMemory,
        error.IsCodeEvaluationFailed => null,
    };
    if (stab) |s| {
        defer {
            allocator.free(s.gz_curve);
        }
        gm_corrected = s.stability.gm_corrected_m;
        gm_check = .{
            .pass = gm_corrected >= mission.gates.min_gm_m,
            .value = gm_corrected,
            .limit = mission.gates.min_gm_m,
        };
        const is_pass = s.is_code.overall == .pass;
        is_code_check = .{
            .pass = if (mission.gates.require_is_code) is_pass else true,
            .value = if (is_pass) 1 else 0,
            .limit = 1,
        };
    }

    // Resistance model validity envelope (Holtrop 1984).
    const res = cargo_resistance.evaluate(.{
        .hull = holtropParticulars(h),
        .speed_mps = 5.0,
    });
    const res_check: Check = .{
        .pass = if (res) |_| true else |_| false,
        .value = h.loa_m / h.beam_m,
        .limit = 14.9,
    };

    const all = era_check.pass and freeboard_check.pass and gm_check.pass and
        is_code_check.pass and res_check.pass;

    return .{
        .era_envelope = era_check,
        .freeboard = freeboard_check,
        .intact_stability = gm_check,
        .is_code_overall = is_code_check,
        .resistance_envelope = res_check,
        .all_pass = all,
        .gm_corrected_m = gm_corrected,
    };
}

pub fn holtropParticulars(h: spec.Hull) @import("yard_resistance").holtrop.HullParticulars {
    return .{
        .L = h.loa_m,
        .B = h.beam_m,
        .T = h.draft_m,
        .displacement_vol = h.displacement_m3,
        .S = h.wetted_surface_m2,
        .C_B = h.cb,
        .C_M = h.cm,
        .C_P = h.cp,
        .C_WP = h.cwp,
        .lcb_pct = h.lcb_pct,
        .c_stern = 0.0,
    };
}

fn testMission(allocator: std.mem.Allocator) !std.json.Parsed(spec.MissionSpec) {
    return spec.parseMission(allocator, spec.test_mission_json);
}

fn testSubmission(allocator: std.mem.Allocator) !std.json.Parsed(spec.Submission) {
    return spec.parseSubmission(allocator, spec.test_submission_json);
}

test "baseline coaster passes all gates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = try testMission(a);
    const s = try testSubmission(a);
    const report = try evaluate(a, m.value, s.value);
    try std.testing.expect(report.era_envelope.pass);
    try std.testing.expect(report.freeboard.pass);
    try std.testing.expect(report.intact_stability.pass);
    try std.testing.expect(report.is_code_overall.pass);
    try std.testing.expect(report.resistance_envelope.pass);
    try std.testing.expect(report.all_pass);
    try std.testing.expect(report.gm_corrected_m > 0.15);
}

test "top-heavy loading fails the stability gate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = try testMission(a);
    const s = try testSubmission(a);
    var sub = s.value;
    // KM_T for a 16 m x 6 m box section is ~6.6 m; KG above it must fail.
    sub.loading.kg_m = 8.5;
    const report = try evaluate(a, m.value, sub);
    try std.testing.expect(!report.intact_stability.pass);
    try std.testing.expect(!report.all_pass);
}

test "oversize hull fails the era envelope" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = try testMission(a);
    const s = try testSubmission(a);
    var sub = s.value;
    sub.hull.loa_m = 200.0;
    const report = try evaluate(a, m.value, sub);
    try std.testing.expect(!report.era_envelope.pass);
    try std.testing.expect(!report.all_pass);
}

test "no-freeboard hull fails the freeboard gate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = try testMission(a);
    const s = try testSubmission(a);
    var sub = s.value;
    sub.hull.draft_m = 8.9;
    sub.hull.depth_m = 9.0;
    const report = try evaluate(a, m.value, sub);
    try std.testing.expect(!report.freeboard.pass);
}

test "degenerate slenderness fails the resistance envelope" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = try testMission(a);
    const s = try testSubmission(a);
    var sub = s.value;
    // L/B = 50: far outside Holtrop validity; must be rejected, not scored.
    sub.hull.beam_m = 2.0;
    sub.hull.loa_m = 100.0;
    const report = try evaluate(a, m.value, sub);
    try std.testing.expect(!report.resistance_envelope.pass);
}
