//! Pareto placement of an objective vector against leaderboard entries.
//! The leaderboard is a frontier, not a scalar ranking: an entry is on the
//! front iff no other entry dominates it.

const std = @import("std");
const spec = @import("spec.zig");

pub const Placement = struct {
    on_front: bool,
    /// Number of existing entries that dominate the candidate.
    dominated_by: u32,
    /// Number of existing entries the candidate dominates.
    dominates: u32,
    entries_compared: u32,
};

/// True iff `a` dominates `b`: at least as good in every objective and
/// strictly better in at least one, respecting each objective's direction.
pub fn dominates(a: []const f64, b: []const f64, objectives: []const spec.Objective) bool {
    std.debug.assert(a.len == b.len and a.len == objectives.len);
    var strictly_better = false;
    for (a, b, objectives) |av, bv, obj| {
        const a_min = if (obj.direction == .min) av else -av;
        const b_min = if (obj.direction == .min) bv else -bv;
        if (a_min > b_min) return false;
        if (a_min < b_min) strictly_better = true;
    }
    return strictly_better;
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

const test_objectives = [_]spec.Objective{
    .{ .id = "days", .direction = .min },
    .{ .id = "cargo", .direction = .max },
};

test "dominance respects direction" {
    // Fewer days AND more cargo: strict dominance.
    try std.testing.expect(dominates(&.{ 10.0, 500.0 }, &.{ 12.0, 400.0 }, &test_objectives));
    // Trade-off (faster but less cargo): no dominance either way.
    try std.testing.expect(!dominates(&.{ 10.0, 400.0 }, &.{ 12.0, 500.0 }, &test_objectives));
    try std.testing.expect(!dominates(&.{ 12.0, 500.0 }, &.{ 10.0, 400.0 }, &test_objectives));
    // Equal vectors do not dominate each other.
    try std.testing.expect(!dominates(&.{ 10.0, 500.0 }, &.{ 10.0, 500.0 }, &test_objectives));
}

test "placement against a small leaderboard" {
    const entries = [_][]const f64{
        &.{ 10.0, 500.0 }, // dominates candidate on both
        &.{ 14.0, 300.0 }, // dominated by candidate
        &.{ 11.0, 350.0 }, // trade-off: faster but less cargo
    };
    const p = place(&.{ 12.0, 400.0 }, &entries, &test_objectives);
    try std.testing.expectEqual(@as(u32, 1), p.dominated_by);
    try std.testing.expectEqual(@as(u32, 1), p.dominates);
    try std.testing.expect(!p.on_front);

    const q = place(&.{ 9.0, 700.0 }, &entries, &test_objectives);
    try std.testing.expect(q.on_front);
    try std.testing.expectEqual(@as(u32, 3), q.dominates);
}
