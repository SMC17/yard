//! Epsilon-Pareto ranking for feasible Yard Arena scorecards.

const std = @import("std");
const types = @import("types.zig");

/// Infeasible entries never dominate and never receive a Pareto rank.
pub fn dominates(a: types.Scorecard, b: types.Scorecard) bool {
    if (!a.feasible or !b.feasible) return false;
    if (a.objectives.len == 0 or a.objectives.len != b.objectives.len) return false;

    var strictly_better = false;
    for (a.objectives, b.objectives) |left, right| {
        if (left.name != right.name or left.direction != right.direction or left.aggregate != right.aggregate) return false;
        const epsilon = @max(left.epsilon, right.epsilon);
        switch (left.direction) {
            .minimize => {
                if (left.value > right.value) return false;
                if (left.value < right.value - epsilon) strictly_better = true;
            },
            .maximize => {
                if (left.value < right.value) return false;
                if (left.value > right.value + epsilon) strictly_better = true;
            },
        }
    }
    return strictly_better;
}

/// Returns ranks parallel to `entries`: 1 is the non-dominated front; 0 means
/// infeasible and excluded. Input ordering does not alter dominance results.
pub fn rankFronts(allocator: std.mem.Allocator, entries: []const types.Scorecard) ![]u32 {
    const ranks = try allocator.alloc(u32, entries.len);
    @memset(ranks, 0);
    var remaining = try allocator.alloc(bool, entries.len);
    defer allocator.free(remaining);
    var selected = try allocator.alloc(bool, entries.len);
    defer allocator.free(selected);

    var unresolved: usize = 0;
    for (entries, 0..) |entry, i| {
        remaining[i] = entry.feasible;
        if (entry.feasible) unresolved += 1;
    }

    var rank: u32 = 1;
    while (unresolved > 0) : (rank += 1) {
        @memset(selected, false);
        var selected_count: usize = 0;
        for (entries, 0..) |candidate, i| {
            if (!remaining[i]) continue;
            var is_dominated = false;
            for (entries, 0..) |other, j| {
                if (i == j or !remaining[j]) continue;
                if (dominates(other, candidate)) {
                    is_dominated = true;
                    break;
                }
            }
            if (!is_dominated) {
                selected[i] = true;
                selected_count += 1;
            }
        }
        if (selected_count == 0) return error.InvalidObjectiveSet;
        for (selected, 0..) |is_selected, i| {
            if (!is_selected) continue;
            ranks[i] = rank;
            remaining[i] = false;
            unresolved -= 1;
        }
    }
    return ranks;
}

fn objectiveSet(cargo: f64, days: f64, cost: f64) [3]types.ObjectiveValue {
    return .{
        .{ .name = .delivered_cargo_t, .direction = .maximize, .aggregate = .mean, .epsilon = 0.0, .value = cargo },
        .{ .name = .mean_transit_days, .direction = .minimize, .aggregate = .mean, .epsilon = 0.0, .value = days },
        .{ .name = .total_cost_units, .direction = .minimize, .aggregate = .fixed, .epsilon = 0.0, .value = cost },
    };
}

fn fixture(feasible: bool, objectives: []const types.ObjectiveValue) types.Scorecard {
    const cargo = if (objectives.len > 0) objectives[0].value else 0.0;
    const cost = if (objectives.len > 2) objectives[2].value else 0.0;
    return .{
        .schema_version = types.scorecard_schema,
        .evaluator_version = types.evaluator_version,
        .evaluator_id = "test",
        .run_id = "run",
        .mission_id = "mission",
        .mission_version = "v0",
        .ruleset_id = "rules",
        .submission_id = "entry",
        .track = .human_ai,
        .mission_sha256 = "m",
        .submission_sha256 = "s",
        .simulation_result_sha256 = "r",
        .backend_version = "test-v1",
        .environment_sha256 = "e",
        .replay_algorithm = "sha256-chain-v1",
        .replay_head_sha256 = "h",
        .replay_event_count = 1,
        .season_commitment_sha256 = "c",
        .seed = 1,
        .scenario_count = 1,
        .feasible = feasible,
        .total_vessels = 1,
        .total_cost_units = cost,
        .total_nominal_cargo_t = cargo,
        .violations = &.{},
        .objectives = if (feasible) objectives else &.{},
    };
}

test "Pareto fronts preserve tradeoffs and rank dominated entries" {
    const objectives_a = objectiveSet(100.0, 100.0, 100.0);
    const objectives_b = objectiveSet(120.0, 120.0, 120.0);
    const objectives_c = objectiveSet(90.0, 110.0, 120.0);
    const impossible_objectives = objectiveSet(1000.0, 1.0, 1.0);
    const entries = [_]types.Scorecard{
        fixture(true, &objectives_a),
        fixture(true, &objectives_b),
        fixture(true, &objectives_c),
        fixture(false, &impossible_objectives),
    };
    const ranks = try rankFronts(std.testing.allocator, &entries);
    defer std.testing.allocator.free(ranks);
    try std.testing.expectEqualSlices(u32, &.{ 1, 1, 2, 0 }, ranks);
}

test "infeasible perfect metrics cannot enter the frontier" {
    const feasible_objectives = objectiveSet(10.0, 10.0, 10.0);
    const impossible_objectives = objectiveSet(1_000_000.0, 0.0, 0.0);
    const feasible = fixture(true, &feasible_objectives);
    const impossible = fixture(false, &impossible_objectives);
    try std.testing.expect(!dominates(impossible, feasible));
}

test "epsilon treats numerical noise as equivalent" {
    var a_objectives = objectiveSet(100.0, 10.0, 10.0);
    var b_objectives = objectiveSet(100.05, 10.0, 10.0);
    a_objectives[0].epsilon = 0.1;
    b_objectives[0].epsilon = 0.1;
    const a = fixture(true, &a_objectives);
    const b = fixture(true, &b_objectives);
    try std.testing.expect(!dominates(a, b));
    try std.testing.expect(!dominates(b, a));
}

test "epsilon dominance is acyclic for cyclic tolerance vectors" {
    const a_objectives = [_]types.ObjectiveValue{
        .{ .name = .delivered_cargo_t, .direction = .minimize, .aggregate = .fixed, .epsilon = 1.0, .value = 0.0 },
        .{ .name = .mean_transit_days, .direction = .minimize, .aggregate = .fixed, .epsilon = 1.0, .value = 1.0 },
        .{ .name = .total_cost_units, .direction = .minimize, .aggregate = .fixed, .epsilon = 1.0, .value = 2.0 },
    };
    const b_objectives = [_]types.ObjectiveValue{
        .{ .name = .delivered_cargo_t, .direction = .minimize, .aggregate = .fixed, .epsilon = 1.0, .value = 2.0 },
        .{ .name = .mean_transit_days, .direction = .minimize, .aggregate = .fixed, .epsilon = 1.0, .value = 0.0 },
        .{ .name = .total_cost_units, .direction = .minimize, .aggregate = .fixed, .epsilon = 1.0, .value = 1.0 },
    };
    const c_objectives = [_]types.ObjectiveValue{
        .{ .name = .delivered_cargo_t, .direction = .minimize, .aggregate = .fixed, .epsilon = 1.0, .value = 1.0 },
        .{ .name = .mean_transit_days, .direction = .minimize, .aggregate = .fixed, .epsilon = 1.0, .value = 2.0 },
        .{ .name = .total_cost_units, .direction = .minimize, .aggregate = .fixed, .epsilon = 1.0, .value = 0.0 },
    };
    const entries = [_]types.Scorecard{
        fixture(true, &a_objectives),
        fixture(true, &b_objectives),
        fixture(true, &c_objectives),
    };
    const ranks = try rankFronts(std.testing.allocator, &entries);
    defer std.testing.allocator.free(ranks);
    try std.testing.expectEqualSlices(u32, &.{ 1, 1, 1 }, ranks);
}
