//! Sail-mission validity gates: era envelope (materials, propulsion,
//! dimensional practice, treaty caps) + intact stability. Rejected designs
//! are never scored.

const std = @import("std");
const naval = @import("yard_naval_arch");
const era = @import("yard_era");
const box_barge = @import("yard_box_barge");
const weathercrit = @import("yard_weathercrit");
const spec = @import("spec.zig");

pub const Error = error{ OutOfMemory, UnknownEra, UnknownMaterial };

pub const Check = struct {
    pass: bool,
    value: f64,
    limit: f64,
};

pub const Report = struct {
    era_envelope: Check,
    /// Number of era violations (value) — zero required.
    era_violations: [era.envelope.max_violations]era.envelope.Violation,
    n_era_violations: usize,
    intact_stability: Check,
    is_code_overall: Check,
    /// Wind heeling vs righting at the reference beam wind — the cap on
    /// how much canvas a hull can carry. Without it, unbounded sail area
    /// dominates every sail mission.
    sail_carrying: Check,
    /// IMO weather criterion (IS Code 2.3), sails struck; value is the
    /// energy margin area_b - area_a [m rad]. Hard-gated only when the
    /// mission sets require_weather_criterion.
    weather_criterion: Check,
    /// Raw criterion outcome regardless of the mission's gate opt-in.
    weather_criterion_pass: bool,
    all_pass: bool,
    gm_corrected_m: f64,
};

/// Steady heel at the reference wind, small-angle: wind heeling moment
/// 0.5 rho_air V^2 A Ch h_ce against righting m g GM. Ch = 1.2 (rig broad-
/// side), h_ce = 0.4 sqrt(A) (geometric centre of a stacked sail plan).
/// Documented v0 proxy for the IMO weather criterion.
pub fn heelAtReferenceWind(sub: spec.Submission, gm_m: f64, wind_mps: f64) f64 {
    const area = sub.rig.area_m2;
    const h_ce = 0.4 * @sqrt(area);
    const m_heel = 0.5 * 1.225 * wind_mps * wind_mps * area * 1.2 * h_ce;
    const mass_kg = sub.hull.displacement_m3 * 1025.0;
    const m_right_per_rad = mass_kg * 9.81 * gm_m;
    if (m_right_per_rad <= 0) return 90.0;
    return std.math.radiansToDegrees(std.math.atan(m_heel / m_right_per_rad));
}

pub fn evaluate(allocator: std.mem.Allocator, mission: spec.MissionSpec, sub: spec.Submission) Error!Report {
    const era_id = std.meta.stringToEnum(era.envelope.EraId, mission.era_id) orelse
        return Error.UnknownEra;
    const material = std.meta.stringToEnum(era.materials.MaterialId, sub.material) orelse
        return Error.UnknownMaterial;

    var violations: [era.envelope.max_violations]era.envelope.Violation = undefined;
    const found = era.envelope.check(era.envelope.get(era_id), .{
        .loa_m = sub.hull.loa_m,
        .beam_m = sub.hull.beam_m,
        .draft_m = sub.hull.draft_m,
        .depth_m = sub.hull.depth_m,
        .displacement_t = sub.hull.displacement_m3 * 1.025,
        .material = material,
        .propulsion = .sail,
    }, &violations);
    const era_check: Check = .{
        .pass = found.len == 0,
        .value = @floatFromInt(found.len),
        .limit = 0,
    };

    var gm_check: Check = .{ .pass = false, .value = 0, .limit = mission.gates.min_gm_m };
    var is_check: Check = .{ .pass = false, .value = 0, .limit = 1 };
    var gm: f64 = 0;
    var curve: [16]weathercrit.GzSample = undefined;
    var n_curve: usize = 0;
    const stab: ?box_barge.Output = box_barge.evaluate(allocator, .{
        .particulars = .{ .L = sub.hull.loa_m, .B = sub.hull.beam_m, .T = sub.hull.draft_m },
        .loading = .{ .kg_m = sub.hull.kg_m, .tanks = &.{} },
    }) catch |err| switch (err) {
        error.OutOfMemory => return Error.OutOfMemory,
        error.IsCodeEvaluationFailed => null,
    };
    if (stab) |s| {
        defer allocator.free(s.gz_curve);
        n_curve = @min(s.gz_curve.len, curve.len);
        for (s.gz_curve[0..n_curve], 0..) |p, i| {
            curve[i] = .{ .angle_deg = p.angle_deg, .gz_m = p.gz_m };
        }
        gm = s.stability.gm_corrected_m;
        gm_check = .{ .pass = gm >= mission.gates.min_gm_m, .value = gm, .limit = mission.gates.min_gm_m };
        const is_pass = s.is_code.overall == .pass;
        is_check = .{
            .pass = if (mission.gates.require_is_code) is_pass else true,
            .value = if (is_pass) 1 else 0,
            .limit = 1,
        };
    }

    const heel = heelAtReferenceWind(sub, gm, mission.gates.gate_wind_mps);
    const sail_check: Check = .{
        .pass = gm > 0 and heel <= mission.gates.max_heel_deg,
        .value = heel,
        .limit = mission.gates.max_heel_deg,
    };

    // IMO weather criterion (IS Code 2.3), sails struck: hull windage plus
    // 10% of the sail plan as bare spars and standing rigging (documented
    // proxy). Always computed; hard gate only when the mission opts in.
    var weather_pass = false;
    var weather_margin: f64 = 0;
    if (n_curve >= 2) {
        const freeboard = sub.hull.depth_m - sub.hull.draft_m;
        const a_hull = sub.hull.loa_m * @max(freeboard, 0.0);
        const a_rig = 0.10 * sub.rig.area_m2;
        const area = a_hull + a_rig;
        const z_centroid = if (area > 0)
            (a_hull * 0.5 * freeboard + a_rig * 0.4 * @sqrt(a_rig)) / area
        else
            0;
        const wc = weathercrit.evaluate(.{
            .lwl_m = sub.hull.loa_m,
            .beam_m = sub.hull.beam_m,
            .draft_m = sub.hull.draft_m,
            .cb = sub.hull.cb,
            .displacement_t = sub.hull.displacement_m3 * 1.025,
            .gm_m = gm,
            .og_m = sub.hull.kg_m - sub.hull.draft_m,
            .windage_area_m2 = area,
            .windage_lever_z_m = z_centroid + sub.hull.draft_m / 2.0,
            .gz_curve = curve[0..n_curve],
        });
        weather_pass = wc.pass;
        weather_margin = wc.area_b_m_rad - wc.area_a_m_rad;
    }
    const weather_check: Check = .{
        .pass = if (mission.gates.require_weather_criterion) weather_pass else true,
        .value = weather_margin,
        .limit = 0,
    };

    return .{
        .era_envelope = era_check,
        .era_violations = violations,
        .n_era_violations = found.len,
        .intact_stability = gm_check,
        .is_code_overall = is_check,
        .sail_carrying = sail_check,
        .weather_criterion = weather_check,
        .weather_criterion_pass = weather_pass,
        .all_pass = era_check.pass and gm_check.pass and is_check.pass and
            sail_check.pass and weather_check.pass,
        .gm_corrected_m = gm,
    };
}

const fixtures = @import("fixtures.zig");

test "Cutty Sark passes gates; steel anachronism dies at the era gate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = try spec.parseMission(a, fixtures.tea_race_mission_json);

    const cutty = try spec.parseSubmission(a, fixtures.cutty_sark_json);
    const ok = try evaluate(a, m.value, cutty.value);
    try std.testing.expect(ok.all_pass);
    try std.testing.expect(ok.gm_corrected_m >= 0.5);

    const steel = try spec.parseSubmission(a, fixtures.steel_anachronism_json);
    const bad = try evaluate(a, m.value, steel.value);
    try std.testing.expect(!bad.era_envelope.pass);
    try std.testing.expect(!bad.all_pass);
    try std.testing.expectEqual(era.envelope.Violation.material_anachronistic, bad.era_violations[0]);
}

test "overcanvassed rig fails the sail-carrying gate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = try spec.parseMission(a, fixtures.tea_race_mission_json);
    const cutty = try spec.parseSubmission(a, fixtures.cutty_sark_json);

    var oversail = cutty.value;
    oversail.rig.area_m2 = 6000.0;
    const r = try evaluate(a, m.value, oversail);
    try std.testing.expect(!r.sail_carrying.pass);
    try std.testing.expect(!r.all_pass);
    // The historical sail plan passes with margin.
    const ok = try evaluate(a, m.value, cutty.value);
    try std.testing.expect(ok.sail_carrying.pass);
    try std.testing.expect(ok.sail_carrying.value < 15.0);
}

test "unknown era or material is an error, not a pass" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = try spec.parseMission(a, fixtures.tea_race_mission_json);
    const cutty = try spec.parseSubmission(a, fixtures.cutty_sark_json);

    var bad_sub = cutty.value;
    bad_sub.material = "unobtainium";
    try std.testing.expectError(Error.UnknownMaterial, evaluate(a, m.value, bad_sub));
}

test "weather criterion is computed and reported for the baseline" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = try spec.parseMission(a, fixtures.tea_race_mission_json);
    const cutty = try spec.parseSubmission(a, fixtures.cutty_sark_json);
    const r = try evaluate(a, m.value, cutty.value);
    // Advisory in m1 (opt-in flag unset): never blocks all_pass...
    try std.testing.expect(r.weather_criterion.pass);
    try std.testing.expect(r.all_pass);
    // ...but the raw outcome and energy margin are computed and finite.
    try std.testing.expect(std.math.isFinite(r.weather_criterion.value));
    // A gate-hardened mission flips the flag and the check binds.
    var hard = m.value;
    hard.gates.require_weather_criterion = true;
    const rh = try evaluate(a, hard, cutty.value);
    try std.testing.expectEqual(r.weather_criterion_pass, rh.weather_criterion.pass);
}
