//! Sail-mission runner: gates -> passage Monte Carlo -> objectives ->
//! Pareto placement. Canonical JSON output, byte-identical for identical
//! inputs. Mirrors mission/src/runner.zig; the two consolidate into one
//! runner once the in-flight fleet work on mission/ lands.

const std = @import("std");
const spec = @import("spec.zig");
const gates = @import("gates.zig");
const voyage = @import("voyage.zig");

pub const Error = error{
    OutOfMemory,
    UnknownObjective,
    UnknownEra,
    UnknownMaterial,
    RouteInvalid,
};

pub const Placement = struct {
    on_front: bool,
    dominated_by: u32,
    dominates: u32,
    entries_compared: u32,
};

pub fn dominates(a: []const f64, b: []const f64, objectives: []const spec.Objective) bool {
    var strictly = false;
    for (a, b, objectives) |av, bv, obj| {
        const am = if (obj.direction == .min) av else -av;
        const bm = if (obj.direction == .min) bv else -bv;
        if (am > bm) return false;
        if (am < bm) strictly = true;
    }
    return strictly;
}

pub fn place(candidate: []const f64, entries: []const []const f64, objectives: []const spec.Objective) Placement {
    var dominated_by: u32 = 0;
    var dominates_n: u32 = 0;
    for (entries) |e| {
        if (dominates(e, candidate, objectives)) dominated_by += 1;
        if (dominates(candidate, e, objectives)) dominates_n += 1;
    }
    return .{
        .on_front = dominated_by == 0,
        .dominated_by = dominated_by,
        .dominates = dominates_n,
        .entries_compared = @intCast(entries.len),
    };
}

pub const Report = struct {
    mission_id: []const u8,
    submission_id: []const u8,
    author: []const u8,
    gate: gates.Report,
    voyage: ?voyage.Aggregate,
    objectives: []const f64,
    placement: ?Placement,
    scored: bool,
};

fn objectiveValue(agg: voyage.Aggregate, id: []const u8) Error!f64 {
    const map = .{
        .{ "passage_days", agg.passage_days },
        .{ "p95_days", agg.p95_days },
        .{ "loss_rate", agg.loss_rate },
        .{ "mean_speed_kn", agg.mean_speed_kn },
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
    seed_override: ?u64,
) Error!Report {
    const gate_report = try gates.evaluate(allocator, mission, sub);

    var objectives = try allocator.alloc(f64, mission.objectives.len);
    errdefer allocator.free(objectives);
    for (objectives) |*o| o.* = std.math.nan(f64);

    var agg: ?voyage.Aggregate = null;
    var scored = false;
    if (gate_report.all_pass) {
        const a = voyage.simulate(allocator, mission, sub, seed_override) catch |err| switch (err) {
            error.OutOfMemory => return Error.OutOfMemory,
            error.RouteInvalid => return Error.RouteInvalid,
        };
        agg = a;
        scored = true;
        for (mission.objectives, 0..) |obj, i| {
            objectives[i] = try objectiveValue(a, obj.id);
            if (!std.math.isFinite(objectives[i])) scored = false;
        }
    }

    return .{
        .mission_id = mission.id,
        .submission_id = sub.id,
        .author = sub.author,
        .gate = gate_report,
        .voyage = agg,
        .objectives = objectives,
        .placement = if (scored) place(objectives, leaderboard, mission.objectives) else null,
        .scored = scored,
    };
}

// --- canonical JSON ----------------------------------------------------------

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
    list.appendSlice(gpa, "{\"schema\":\"yard-sail-mission-result/v0\",\"mission\":") catch return Error.OutOfMemory;
    try appendJsonString(list, gpa, report.mission_id);
    list.appendSlice(gpa, ",\"submission\":") catch return Error.OutOfMemory;
    try appendJsonString(list, gpa, report.submission_id);
    list.appendSlice(gpa, ",\"author\":") catch return Error.OutOfMemory;
    try appendJsonString(list, gpa, report.author);

    list.appendSlice(gpa, ",\"gates\":{") catch return Error.OutOfMemory;
    try appendCheck(list, gpa, "era_envelope", report.gate.era_envelope);
    if (report.gate.n_era_violations > 0) {
        list.appendSlice(gpa, ",\"era_violations\":[") catch return Error.OutOfMemory;
        for (report.gate.era_violations[0..report.gate.n_era_violations], 0..) |v, i| {
            if (i > 0) list.append(gpa, ',') catch return Error.OutOfMemory;
            try appendJsonString(list, gpa, @tagName(v));
        }
        list.append(gpa, ']') catch return Error.OutOfMemory;
    }
    list.append(gpa, ',') catch return Error.OutOfMemory;
    try appendCheck(list, gpa, "intact_stability", report.gate.intact_stability);
    list.append(gpa, ',') catch return Error.OutOfMemory;
    try appendCheck(list, gpa, "is_code_overall", report.gate.is_code_overall);
    list.append(gpa, ',') catch return Error.OutOfMemory;
    try appendCheck(list, gpa, "sail_carrying", report.gate.sail_carrying);
    list.append(gpa, ',') catch return Error.OutOfMemory;
    try appendCheck(list, gpa, "weather_criterion", report.gate.weather_criterion);
    try appendFmt(list, gpa, ",\"weather_criterion_raw\":{}", .{report.gate.weather_criterion_pass});
    try appendFmt(list, gpa, ",\"all_pass\":{}}}", .{report.gate.all_pass});

    if (report.voyage) |v| {
        try appendFmt(list, gpa, ",\"voyage\":{{\"runs\":{d},\"losses\":{d},\"base_seed\":{d},\"route_nm\":", .{ v.runs, v.losses, v.base_seed });
        try appendF64(list, gpa, v.route_nm);
        list.appendSlice(gpa, ",\"passage_days\":") catch return Error.OutOfMemory;
        try appendF64(list, gpa, v.passage_days);
        list.appendSlice(gpa, ",\"p95_days\":") catch return Error.OutOfMemory;
        try appendF64(list, gpa, v.p95_days);
        list.appendSlice(gpa, ",\"loss_rate\":") catch return Error.OutOfMemory;
        try appendF64(list, gpa, v.loss_rate);
        list.appendSlice(gpa, ",\"mean_speed_kn\":") catch return Error.OutOfMemory;
        try appendF64(list, gpa, v.mean_speed_kn);
        list.append(gpa, '}') catch return Error.OutOfMemory;
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

pub fn renderEntryLine(list: *std.ArrayList(u8), gpa: std.mem.Allocator, report: Report) Error!void {
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

const fixtures = @import("fixtures.zig");

test "end-to-end: Cutty Sark scored, steel unscored, output deterministic JSON" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const m = try spec.parseMission(a, fixtures.tea_race_mission_json);
    const cutty = try spec.parseSubmission(a, fixtures.cutty_sark_json);
    const steel = try spec.parseSubmission(a, fixtures.steel_anachronism_json);

    const r1 = try evaluate(a, m.value, cutty.value, &.{}, null);
    const r2 = try evaluate(a, m.value, cutty.value, &.{}, null);
    try std.testing.expect(r1.scored);

    var out1: std.ArrayList(u8) = .empty;
    var out2: std.ArrayList(u8) = .empty;
    try renderReportJson(&out1, a, r1, m.value.objectives);
    try renderReportJson(&out2, a, r2, m.value.objectives);
    try std.testing.expectEqualStrings(out1.items, out2.items);
    _ = try std.json.parseFromSlice(std.json.Value, a, out1.items, .{});

    const rs = try evaluate(a, m.value, steel.value, &.{}, null);
    try std.testing.expect(!rs.scored);
    try std.testing.expect(rs.voyage == null);

    // Leaderboard round trip: the Indiaman is dominated by the clipper on
    // passage time but the frontier judges all objectives.
    var line: std.ArrayList(u8) = .empty;
    try renderEntryLine(&line, a, r1);
    const entries = try parseLeaderboard(a, line.items, m.value.id, m.value.objectives.len);
    try std.testing.expectEqual(@as(usize, 1), entries.len);
}
