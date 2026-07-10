//! Mission evaluation runner: gates -> Monte Carlo voyage -> objectives ->
//! Pareto placement. Output is canonical JSON: field order is fixed by this
//! file, so identical inputs produce byte-identical reports.

const std = @import("std");
const spec = @import("spec.zig");
const gates = @import("gates.zig");
const voyage = @import("voyage.zig");
const pareto = @import("pareto.zig");

pub const Error = error{
    OutOfMemory,
    UnknownObjective,
    RouteInvalid,
    ResistanceFailed,
};

pub const Report = struct {
    mission_id: []const u8,
    submission_id: []const u8,
    author: []const u8,
    gate: gates.Report,
    /// Present iff all gates passed and the voyage model accepted the vessel.
    voyage: ?voyage.Aggregate,
    /// Reason voyage is absent despite passing gates (e.g. insufficient power).
    voyage_rejection: ?[]const u8,
    /// Objective values aligned with the mission's objective declarations.
    objectives: []const f64,
    placement: ?pareto.Placement,
    /// Scored = gates passed, voyage ran, all objectives finite.
    scored: bool,
};

fn objectiveValue(agg: voyage.Aggregate, id: []const u8) Error!f64 {
    const map = .{
        .{ "voyage_days", agg.mean_days },
        .{ "p95_days", agg.p95_days },
        .{ "loss_rate", agg.loss_rate },
        .{ "cargo_delivered_t", agg.cargo_delivered_t },
        .{ "transport_cost_index", agg.transport_cost_index },
        .{ "calm_speed_mps", agg.calm_speed_mps },
    };
    inline for (map) |entry| {
        if (std.mem.eql(u8, id, entry[0])) return entry[1];
    }
    return Error.UnknownObjective;
}

pub fn evaluate(
    allocator: std.mem.Allocator,
    mission: spec.MissionSpec,
    sub: spec.Submission,
    leaderboard: []const []const f64,
) Error!Report {
    const gate_report = try gates.evaluate(allocator, mission, sub);

    var objectives = try allocator.alloc(f64, mission.objectives.len);
    errdefer allocator.free(objectives);
    for (objectives) |*o| o.* = std.math.nan(f64);

    var agg: ?voyage.Aggregate = null;
    var rejection: ?[]const u8 = null;
    var scored = false;

    if (gate_report.all_pass) {
        if (voyage.simulate(allocator, mission, sub)) |a| {
            agg = a;
            scored = true;
            for (mission.objectives, 0..) |obj, i| {
                objectives[i] = try objectiveValue(a, obj.id);
                if (!std.math.isFinite(objectives[i])) scored = false;
            }
        } else |err| switch (err) {
            error.OutOfMemory => return Error.OutOfMemory,
            error.RouteInvalid => return Error.RouteInvalid,
            error.ResistanceFailed => return Error.ResistanceFailed,
            error.InsufficientPower => rejection = "insufficient_power",
        }
    }

    const placement: ?pareto.Placement = if (scored)
        pareto.place(objectives, leaderboard, mission.objectives)
    else
        null;

    return .{
        .mission_id = mission.id,
        .submission_id = sub.id,
        .author = sub.author,
        .gate = gate_report,
        .voyage = agg,
        .voyage_rejection = rejection,
        .objectives = objectives,
        .placement = placement,
        .scored = scored,
    };
}

// --- canonical JSON rendering ------------------------------------------------

fn appendFmt(list: *std.ArrayList(u8), gpa: std.mem.Allocator, comptime fmt: []const u8, args: anytype) Error!void {
    const s = std.fmt.allocPrint(gpa, fmt, args) catch return Error.OutOfMemory;
    defer gpa.free(s);
    list.appendSlice(gpa, s) catch return Error.OutOfMemory;
}

fn appendJsonString(list: *std.ArrayList(u8), gpa: std.mem.Allocator, s: []const u8) Error!void {
    list.append(gpa, '"') catch return Error.OutOfMemory;
    for (s) |c| {
        switch (c) {
            '"' => list.appendSlice(gpa, "\\\"") catch return Error.OutOfMemory,
            '\\' => list.appendSlice(gpa, "\\\\") catch return Error.OutOfMemory,
            '\n' => list.appendSlice(gpa, "\\n") catch return Error.OutOfMemory,
            '\r' => list.appendSlice(gpa, "\\r") catch return Error.OutOfMemory,
            '\t' => list.appendSlice(gpa, "\\t") catch return Error.OutOfMemory,
            else => if (c < 0x20) {
                try appendFmt(list, gpa, "\\u{x:0>4}", .{c});
            } else {
                list.append(gpa, c) catch return Error.OutOfMemory;
            },
        }
    }
    list.append(gpa, '"') catch return Error.OutOfMemory;
}

fn appendF64(list: *std.ArrayList(u8), gpa: std.mem.Allocator, v: f64) Error!void {
    if (std.math.isFinite(v)) {
        try appendFmt(list, gpa, "{d}", .{v});
    } else {
        // Non-finite values are unscoreable; JSON has no inf/nan.
        list.appendSlice(gpa, "null") catch return Error.OutOfMemory;
    }
}

fn appendCheck(list: *std.ArrayList(u8), gpa: std.mem.Allocator, name: []const u8, c: gates.Check) Error!void {
    try appendFmt(list, gpa, "\"{s}\":{{\"pass\":{},\"value\":", .{ name, c.pass });
    try appendF64(list, gpa, c.value);
    list.appendSlice(gpa, ",\"limit\":") catch return Error.OutOfMemory;
    try appendF64(list, gpa, c.limit);
    list.append(gpa, '}') catch return Error.OutOfMemory;
}

pub fn renderReportJson(
    list: *std.ArrayList(u8),
    gpa: std.mem.Allocator,
    report: Report,
    objectives: []const spec.Objective,
) Error!void {
    list.appendSlice(gpa, "{\"schema\":\"yard-mission-result/v0\",\"mission\":") catch return Error.OutOfMemory;
    try appendJsonString(list, gpa, report.mission_id);
    list.appendSlice(gpa, ",\"submission\":") catch return Error.OutOfMemory;
    try appendJsonString(list, gpa, report.submission_id);
    list.appendSlice(gpa, ",\"author\":") catch return Error.OutOfMemory;
    try appendJsonString(list, gpa, report.author);

    list.appendSlice(gpa, ",\"gates\":{") catch return Error.OutOfMemory;
    try appendCheck(list, gpa, "era_envelope", report.gate.era_envelope);
    list.append(gpa, ',') catch return Error.OutOfMemory;
    try appendCheck(list, gpa, "freeboard", report.gate.freeboard);
    list.append(gpa, ',') catch return Error.OutOfMemory;
    try appendCheck(list, gpa, "intact_stability", report.gate.intact_stability);
    list.append(gpa, ',') catch return Error.OutOfMemory;
    try appendCheck(list, gpa, "is_code_overall", report.gate.is_code_overall);
    list.append(gpa, ',') catch return Error.OutOfMemory;
    try appendCheck(list, gpa, "resistance_envelope", report.gate.resistance_envelope);
    try appendFmt(list, gpa, ",\"all_pass\":{}}}", .{report.gate.all_pass});

    if (report.voyage) |v| {
        try appendFmt(list, gpa, ",\"voyage\":{{\"runs\":{d},\"losses\":{d},\"route_nm\":", .{ v.runs, v.losses });
        try appendF64(list, gpa, v.route_nm);
        list.appendSlice(gpa, ",\"calm_speed_mps\":") catch return Error.OutOfMemory;
        try appendF64(list, gpa, v.calm_speed_mps);
        list.appendSlice(gpa, ",\"mean_days\":") catch return Error.OutOfMemory;
        try appendF64(list, gpa, v.mean_days);
        list.appendSlice(gpa, ",\"p95_days\":") catch return Error.OutOfMemory;
        try appendF64(list, gpa, v.p95_days);
        list.appendSlice(gpa, ",\"loss_rate\":") catch return Error.OutOfMemory;
        try appendF64(list, gpa, v.loss_rate);
        list.appendSlice(gpa, ",\"cargo_delivered_t\":") catch return Error.OutOfMemory;
        try appendF64(list, gpa, v.cargo_delivered_t);
        list.appendSlice(gpa, ",\"transport_cost_index\":") catch return Error.OutOfMemory;
        try appendF64(list, gpa, v.transport_cost_index);
        list.append(gpa, '}') catch return Error.OutOfMemory;
    }
    if (report.voyage_rejection) |reason| {
        list.appendSlice(gpa, ",\"voyage_rejection\":") catch return Error.OutOfMemory;
        try appendJsonString(list, gpa, reason);
    }

    list.appendSlice(gpa, ",\"objectives\":[") catch return Error.OutOfMemory;
    for (objectives, report.objectives, 0..) |obj, val, i| {
        if (i > 0) list.append(gpa, ',') catch return Error.OutOfMemory;
        list.appendSlice(gpa, "{\"id\":") catch return Error.OutOfMemory;
        try appendJsonString(list, gpa, obj.id);
        try appendFmt(list, gpa, ",\"direction\":\"{s}\",\"value\":", .{@tagName(obj.direction)});
        try appendF64(list, gpa, val);
        list.append(gpa, '}') catch return Error.OutOfMemory;
    }
    list.append(gpa, ']') catch return Error.OutOfMemory;

    if (report.placement) |p| {
        try appendFmt(
            list,
            gpa,
            ",\"pareto\":{{\"on_front\":{},\"dominated_by\":{d},\"dominates\":{d},\"entries_compared\":{d}}}",
            .{ p.on_front, p.dominated_by, p.dominates, p.entries_compared },
        );
    }

    try appendFmt(list, gpa, ",\"scored\":{}}}", .{report.scored});
    list.append(gpa, '\n') catch return Error.OutOfMemory;
}

/// One leaderboard JSONL line for a scored report.
pub fn renderEntryLine(
    list: *std.ArrayList(u8),
    gpa: std.mem.Allocator,
    report: Report,
) Error!void {
    list.appendSlice(gpa, "{\"mission\":") catch return Error.OutOfMemory;
    try appendJsonString(list, gpa, report.mission_id);
    list.appendSlice(gpa, ",\"id\":") catch return Error.OutOfMemory;
    try appendJsonString(list, gpa, report.submission_id);
    list.appendSlice(gpa, ",\"author\":") catch return Error.OutOfMemory;
    try appendJsonString(list, gpa, report.author);
    list.appendSlice(gpa, ",\"objectives\":[") catch return Error.OutOfMemory;
    for (report.objectives, 0..) |v, i| {
        if (i > 0) list.append(gpa, ',') catch return Error.OutOfMemory;
        try appendF64(list, gpa, v);
    }
    list.appendSlice(gpa, "]}\n") catch return Error.OutOfMemory;
}

const LeaderboardLine = struct {
    mission: []const u8,
    id: []const u8,
    author: []const u8 = "",
    objectives: []const f64,
};

/// Parse leaderboard JSONL, keeping only entries for `mission_id` with the
/// expected objective count. Returned slices are arena-owned.
pub fn parseLeaderboard(
    arena: std.mem.Allocator,
    text: []const u8,
    mission_id: []const u8,
    n_objectives: usize,
) Error![]const []const f64 {
    var entries: std.ArrayList([]const f64) = .empty;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        const parsed = std.json.parseFromSliceLeaky(LeaderboardLine, arena, trimmed, .{
            .ignore_unknown_fields = true,
        }) catch continue;
        if (!std.mem.eql(u8, parsed.mission, mission_id)) continue;
        if (parsed.objectives.len != n_objectives) continue;
        entries.append(arena, parsed.objectives) catch return Error.OutOfMemory;
    }
    return entries.toOwnedSlice(arena) catch return Error.OutOfMemory;
}

test "end-to-end evaluate + render is deterministic and scored" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const m = try spec.parseMission(a, spec.test_mission_json);
    const s = try spec.parseSubmission(a, spec.test_submission_json);

    const report1 = try evaluate(a, m.value, s.value, &.{});
    const report2 = try evaluate(a, m.value, s.value, &.{});

    var out1: std.ArrayList(u8) = .empty;
    var out2: std.ArrayList(u8) = .empty;
    try renderReportJson(&out1, a, report1, m.value.objectives);
    try renderReportJson(&out2, a, report2, m.value.objectives);

    try std.testing.expect(report1.scored);
    try std.testing.expectEqualStrings(out1.items, out2.items);
    // Output must be valid JSON.
    const parsed = try std.json.parseFromSlice(std.json.Value, a, out1.items, .{});
    _ = parsed;
}

test "failed gates produce an unscored report with no voyage" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const m = try spec.parseMission(a, spec.test_mission_json);
    const s = try spec.parseSubmission(a, spec.test_submission_json);
    var bad = s.value;
    bad.loading.kg_m = 8.5;

    const report = try evaluate(a, m.value, bad, &.{});
    try std.testing.expect(!report.scored);
    try std.testing.expect(report.voyage == null);
    try std.testing.expect(report.placement == null);
}

test "leaderboard round trip: render entry then place a new submission" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const m = try spec.parseMission(a, spec.test_mission_json);
    const s = try spec.parseSubmission(a, spec.test_submission_json);

    const baseline = try evaluate(a, m.value, s.value, &.{});
    var line: std.ArrayList(u8) = .empty;
    try renderEntryLine(&line, a, baseline);

    const entries = try parseLeaderboard(a, line.items, m.value.id, m.value.objectives.len);
    try std.testing.expectEqual(@as(usize, 1), entries.len);

    // A faster variant must dominate the baseline on voyage_days at equal cargo.
    var boosted = s.value;
    boosted.propulsion.installed_kw = 8000.0;
    const fast = try evaluate(a, m.value, boosted, entries);
    try std.testing.expect(fast.scored);
    try std.testing.expect(fast.placement != null);
    // Higher power costs more energy per tonne: expect a trade-off, both on front.
    try std.testing.expect(fast.placement.?.on_front);
}
