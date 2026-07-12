//! Governed, deterministic 1778 historical conflict screening model.

pub const types = @import("types.zig");
pub const policy = @import("policy.zig");
pub const simulation = @import("simulation.zig");
pub const arena = @import("yard_arena");

test {
    _ = types;
    _ = policy;
    _ = simulation;
}

test "sourced example is policy-valid, deterministic, conserved, and chained" {
    const std = @import("std");
    const bytes = @embedFile("../scenarios/atlantic-convoy-1778.json");
    var parsed = try std.json.parseFromSlice(types.Scenario, std.testing.allocator, bytes, .{});
    defer parsed.deinit();

    var violations_buffer: [policy.max_violations]policy.Violation = undefined;
    const violations = try policy.validate(parsed.value, &violations_buffer);
    try std.testing.expectEqual(@as(usize, 0), violations.len);

    var first_memory = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer first_memory.deinit();
    const first = try simulation.simulate(first_memory.allocator(), parsed.value);
    var second_memory = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer second_memory.deinit();
    const second = try simulation.simulate(second_memory.allocator(), parsed.value);
    try std.testing.expectEqualStrings(&first.summary.replay_head_sha256, &second.summary.replay_head_sha256);
    try std.testing.expect(first.summary.conservation.crew);
    try std.testing.expect(first.summary.conservation.ammunition);
    try std.testing.expect(first.summary.conservation.powder);

    const views = try first_memory.allocator().alloc(arena.replay.Event, first.replay_events.len);
    for (views, first.replay_events) |*view, *event| view.* = event.view();
    try std.testing.expect(arena.replay.verify(views));
    views[views.len - 1].payload = "tampered";
    try std.testing.expect(!arena.replay.verify(views));
}

test "policy rejects modern sensing, propulsion, and command links" {
    const std = @import("std");
    const bytes = @embedFile("../scenarios/atlantic-convoy-1778.json");
    var parsed = try std.json.parseFromSlice(types.Scenario, std.testing.allocator, bytes, .{});
    defer parsed.deinit();
    var modern = [_]types.Capability{ .wooden_primary_structure, .canvas_sail, .sail_propulsion, .human_lookout, .signal_flags, .manual_pump, .smoothbore_muzzle_loading_cannon, .black_powder, .solid_round_shot, .radar, .guided_weapon, .diesel };
    const vessels = try std.testing.allocator.dupe(types.Vessel, parsed.value.vessels);
    defer std.testing.allocator.free(vessels);
    vessels[0].capabilities = &modern;
    vessels[0].command.signal = .data_link;
    var scenario = parsed.value;
    scenario.vessels = vessels;
    var buffer: [policy.max_violations]policy.Violation = undefined;
    const violations = try policy.validate(scenario, &buffer);
    var anachronisms: usize = 0;
    var signal_mismatch = false;
    var signal_anachronism = false;
    for (violations) |violation| {
        if (violation.code == .anachronistic_capability) anachronisms += 1;
        if (violation.code == .signal_capability_mismatch) signal_mismatch = true;
        if (violation.code == .anachronistic_signal) signal_anachronism = true;
    }
    try std.testing.expectEqual(@as(usize, 3), anachronisms);
    try std.testing.expect(signal_mismatch);
    try std.testing.expect(signal_anachronism);
    try std.testing.expectError(error.InvalidScenario, simulation.simulate(std.testing.allocator, scenario));
}

test "policy rejects an unsupported year and unproven parameter" {
    const std = @import("std");
    const bytes = @embedFile("../scenarios/atlantic-convoy-1778.json");
    var parsed = try std.json.parseFromSlice(types.Scenario, std.testing.allocator, bytes, .{});
    defer parsed.deinit();
    var scenario = parsed.value;
    scenario.year = 2026;
    scenario.environment.wind_speed_mps.source_id = "missing-source";
    var buffer: [policy.max_violations]policy.Violation = undefined;
    const violations = try policy.validate(scenario, &buffer);
    var year_rejected = false;
    var source_rejected = false;
    for (violations) |violation| {
        if (violation.code == .year_outside_governed_scope) year_rejected = true;
        if (violation.code == .source_reference_unknown) source_rejected = true;
    }
    try std.testing.expect(year_rejected);
    try std.testing.expect(source_rejected);
}

test "policy bounds adversarial violations and rejects zero powder charge" {
    const std = @import("std");
    const bytes = @embedFile("../scenarios/atlantic-convoy-1778.json");
    var parsed = try std.json.parseFromSlice(types.Scenario, std.testing.allocator, bytes, .{});
    defer parsed.deinit();

    const repeated = try std.testing.allocator.alloc(types.Vessel, policy.max_vessels);
    defer std.testing.allocator.free(repeated);
    @memset(repeated, parsed.value.vessels[0]);
    var amplified = parsed.value;
    amplified.vessels = repeated;
    var overflow_buffer: [policy.max_violations]policy.Violation = undefined;
    try std.testing.expectError(error.TooManyViolations, policy.validate(amplified, &overflow_buffer));

    const vessels = try std.testing.allocator.dupe(types.Vessel, parsed.value.vessels);
    defer std.testing.allocator.free(vessels);
    vessels[0].gunnery.powder_per_round_kg = .{
        .central = 0,
        .minimum = 0,
        .maximum = 0,
        .source_id = "yard-aggregate-assumptions-v0",
    };
    var zero_charge = parsed.value;
    zero_charge.vessels = vessels;
    var buffer: [policy.max_violations]policy.Violation = undefined;
    const violations = try policy.validate(zero_charge, &buffer);
    var rejected = false;
    for (violations) |violation| {
        if (violation.code == .invalid_numeric_range) rejected = true;
    }
    try std.testing.expect(rejected);
    try std.testing.expectError(error.InvalidScenario, simulation.simulate(std.testing.allocator, zero_charge));
}

test "policy rejects work beyond the public resource envelope" {
    const std = @import("std");
    const bytes = @embedFile("../scenarios/atlantic-convoy-1778.json");
    var parsed = try std.json.parseFromSlice(types.Scenario, std.testing.allocator, bytes, .{});
    defer parsed.deinit();
    var scenario = parsed.value;
    scenario.max_steps = policy.max_steps + 1;
    var buffer: [policy.max_violations]policy.Violation = undefined;
    const violations = try policy.validate(scenario, &buffer);
    try std.testing.expectEqual(@as(usize, 1), violations.len);
    try std.testing.expectEqual(policy.ViolationCode.resource_limit_exceeded, violations[0].code);
}

test "scenario provenance changes the result and replay commitment" {
    const std = @import("std");
    const bytes = @embedFile("../scenarios/atlantic-convoy-1778.json");
    var parsed = try std.json.parseFromSlice(types.Scenario, std.testing.allocator, bytes, .{});
    defer parsed.deinit();
    var original_memory = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer original_memory.deinit();
    const original = try simulation.simulate(original_memory.allocator(), parsed.value);

    const sources = try std.testing.allocator.dupe(types.Source, parsed.value.sources);
    defer std.testing.allocator.free(sources);
    const vessels = try std.testing.allocator.dupe(types.Vessel, parsed.value.vessels);
    defer std.testing.allocator.free(vessels);
    sources[0].note = "mutated provenance note";
    vessels[0].role = .dispatch_sloop;
    vessels[0].displacement_t = 99_999;
    vessels[0].gunnery.shot_mass_kg = 1_000;
    var mutated_scenario = parsed.value;
    mutated_scenario.title = "mutated counterfactual title";
    mutated_scenario.sources = sources;
    mutated_scenario.vessels = vessels;
    var mutated_memory = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer mutated_memory.deinit();
    const mutated = try simulation.simulate(mutated_memory.allocator(), mutated_scenario);

    try std.testing.expect(!std.mem.eql(u8, &original.summary.scenario_sha256, &mutated.summary.scenario_sha256));
    try std.testing.expect(!std.mem.eql(u8, &original.summary.replay_head_sha256, &mutated.summary.replay_head_sha256));
}

test "extreme conversion inputs reject or saturate without trapping" {
    const std = @import("std");
    const bytes = @embedFile("../scenarios/atlantic-convoy-1778.json");
    var parsed = try std.json.parseFromSlice(types.Scenario, std.testing.allocator, bytes, .{});
    defer parsed.deinit();
    const vessels = try std.testing.allocator.dupe(types.Vessel, parsed.value.vessels);
    defer std.testing.allocator.free(vessels);

    vessels[0].command.order_delay_seconds = .{
        .central = 1.0e300,
        .minimum = 1.0e300,
        .maximum = 1.0e300,
        .source_id = "yard-aggregate-assumptions-v0",
    };
    var excessive_delay = parsed.value;
    excessive_delay.vessels = vessels;
    try std.testing.expectError(error.InvalidScenario, simulation.simulate(std.testing.allocator, excessive_delay));

    vessels[0].command.order_delay_seconds = parsed.value.vessels[0].command.order_delay_seconds;
    vessels[0].gunnery.powder_kg = policy.max_scalar;
    vessels[0].gunnery.powder_per_round_kg = .{
        .central = policy.min_positive_scalar,
        .minimum = policy.min_positive_scalar,
        .maximum = policy.min_positive_scalar,
        .source_id = "yard-aggregate-assumptions-v0",
    };
    var extreme_ratio = parsed.value;
    extreme_ratio.vessels = vessels;
    extreme_ratio.max_steps = 1;
    var memory = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer memory.deinit();
    const run = try simulation.simulate(memory.allocator(), extreme_ratio);
    try std.testing.expect(run.summary.conservation.ammunition);
    try std.testing.expect(run.summary.conservation.powder);
}

test "morale threshold produces surrender and hull threshold produces disengagement" {
    const std = @import("std");
    const bytes = @embedFile("../scenarios/atlantic-convoy-1778.json");
    var parsed = try std.json.parseFromSlice(types.Scenario, std.testing.allocator, bytes, .{});
    defer parsed.deinit();
    const source_id = "yard-aggregate-assumptions-v0";

    {
        const vessels = try std.testing.allocator.dupe(types.Vessel, parsed.value.vessels);
        defer std.testing.allocator.free(vessels);
        vessels[2].crew.initial_morale = .{ .central = 0.05, .minimum = 0.05, .maximum = 0.05, .source_id = source_id };
        vessels[2].crew.surrender_morale_threshold = 0.10;
        var scenario = parsed.value;
        scenario.vessels = vessels;
        var memory = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer memory.deinit();
        const run = try simulation.simulate(memory.allocator(), scenario);
        try std.testing.expectEqual(types.VesselStatus.surrendered, run.outcomes[2].status);
    }

    {
        const vessels = try std.testing.allocator.dupe(types.Vessel, parsed.value.vessels);
        defer std.testing.allocator.free(vessels);
        var scenario = parsed.value;
        scenario.vessels = vessels;
        scenario.initial_range_m = .{ .central = 0, .minimum = 0, .maximum = 0, .source_id = source_id };
        scenario.environment.wind_speed_mps = .{ .central = 0, .minimum = 0, .maximum = 0, .source_id = source_id };
        scenario.environment.sea_severity = .{ .central = 0, .minimum = 0, .maximum = 0, .source_id = source_id };
        scenario.environment.visibility_fraction = .{ .central = 1, .minimum = 1, .maximum = 1, .source_id = source_id };
        scenario.max_steps = 2;
        vessels[0].command.order_delay_seconds = .{ .central = 0, .minimum = 0, .maximum = 0, .source_id = source_id };
        vessels[0].command.signal_failure_probability = .{ .central = 0, .minimum = 0, .maximum = 0, .source_id = source_id };
        vessels[0].crew.initial_morale = .{ .central = 1, .minimum = 1, .maximum = 1, .source_id = source_id };
        vessels[0].crew.training_fraction = .{ .central = 1, .minimum = 1, .maximum = 1, .source_id = source_id };
        vessels[0].gunnery.hit_probability_at_reference = .{ .central = 1, .minimum = 1, .maximum = 1, .source_id = source_id };
        vessels[0].gunnery.damage_points_per_hit = .{ .central = 1, .minimum = 1, .maximum = 1, .source_id = source_id };
        vessels[0].gunnery.reload_seconds = .{ .central = 1, .minimum = 1, .maximum = 1, .source_id = source_id };
        vessels[2].crew.surrender_morale_threshold = 0;
        vessels[2].damage_control.withdrawal_hull_fraction = 0.99;
        var memory = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer memory.deinit();
        const run = try simulation.simulate(memory.allocator(), scenario);
        try std.testing.expectEqual(types.VesselStatus.disengaged, run.outcomes[2].status);
    }
}
