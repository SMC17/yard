//! Deterministic, simultaneous-step aggregate engagement simulation.
//!
//! This is deliberately not a targeting or exterior-ballistics model. It is a
//! period-governed screening model for uncertainty, logistics, command delay,
//! morale, damage control, surrender, and disengagement.

const std = @import("std");
const arena = @import("yard_arena");
const policy = @import("policy.zig");
const types = @import("types.zig");

pub const Error = error{ InvalidScenario, OutOfMemory };

pub const Run = struct {
    outcomes: []types.VesselOutcome,
    summary: types.Summary,
    replay_events: []arena.replay.OwnedEvent,
};

const State = struct {
    status: types.VesselStatus = .active,
    crew: u32,
    rounds: u32,
    powder_kg: f64,
    hull: f64,
    fire: f64 = 0,
    flooding: f64 = 0,
    morale: f64,
    training: f64,
    command_active_step: u32,
    command_failed: bool,
    reload_steps: u32,
    powder_per_round_kg: f64,
    effective_range_m: f64,
    base_hit_probability: f64,
    damage_points_per_hit: f64,
    crew_loss_probability: f64,
    fire_probability: f64,
    flooding_probability: f64,
    fire_suppression: f64,
    pumping: f64,
};

const Pending = struct {
    hull_damage: f64 = 0,
    crew_loss: u32 = 0,
    fire: f64 = 0,
    flooding: f64 = 0,
};

const streams = struct {
    const environment: u8 = 20;
    const command: u8 = 21;
    const parameters: u8 = 22;
    const hit: u8 = 23;
    const damage: u8 = 24;
};

pub fn simulate(allocator: std.mem.Allocator, scenario: types.Scenario) Error!Run {
    const canonical = std.json.Stringify.valueAlloc(allocator, scenario, .{}) catch return Error.OutOfMemory;
    defer allocator.free(canonical);
    return simulateBound(allocator, scenario, sha256Hex(canonical));
}

/// Runs a scenario while binding its exact source artifact digest into both
/// the replay chain and result. CLI callers pass the hash of the input bytes;
/// typed callers use `simulate`, which binds deterministic struct JSON.
pub fn simulateBound(
    allocator: std.mem.Allocator,
    scenario: types.Scenario,
    scenario_sha256: [64]u8,
) Error!Run {
    var violations_buffer: [policy.max_violations]policy.Violation = undefined;
    const violations = policy.validate(scenario, &violations_buffer) catch return Error.InvalidScenario;
    if (violations.len != 0) return Error.InvalidScenario;

    const states = allocator.alloc(State, scenario.vessels.len) catch return Error.OutOfMemory;
    const pending = allocator.alloc(Pending, scenario.vessels.len) catch return Error.OutOfMemory;
    const outcomes = allocator.alloc(types.VesselOutcome, scenario.vessels.len) catch return Error.OutOfMemory;
    var events: std.ArrayList(arena.replay.OwnedEvent) = .empty;
    var chain: arena.replay.Chain = .{};

    const initial_range = sample(scenario.seed, streams.parameters, 0, scenario.initial_range_m);
    const start_payload = std.fmt.allocPrint(allocator, "scenario={s};scenario_sha256={s};year={d};seed={d};vessels={d};backend={s};initial_range_m={d:.6}", .{
        scenario.scenario_id, &scenario_sha256, scenario.year, scenario.seed, scenario.vessels.len, types.backend_id, initial_range,
    }) catch return Error.OutOfMemory;
    events.append(allocator, chain.append("run_started", start_payload)) catch return Error.OutOfMemory;

    for (scenario.vessels, states, 0..) |vessel, *state, index| {
        const base: u64 = @as(u64, @intCast(index)) * 32;
        const delay = sample(scenario.seed, streams.command, base, vessel.command.order_delay_seconds);
        const failure_p = sample(scenario.seed, streams.command, base + 1, vessel.command.signal_failure_probability);
        const failed = draw(scenario.seed, streams.command, base + 2) < failure_p;
        state.* = .{
            .crew = vessel.crew.complement,
            .rounds = vessel.gunnery.shot_rounds,
            .powder_kg = vessel.gunnery.powder_kg,
            .hull = vessel.damage_control.hull_integrity_points,
            .morale = sample(scenario.seed, streams.parameters, base + 3, vessel.crew.initial_morale),
            .training = sample(scenario.seed, streams.parameters, base + 14, vessel.crew.training_fraction),
            .command_active_step = @intFromFloat(@ceil(delay / @as(f64, @floatFromInt(scenario.timestep_seconds)))),
            .command_failed = failed,
            .reload_steps = @max(1, @as(u32, @intFromFloat(@ceil(sample(scenario.seed, streams.parameters, base + 4, vessel.gunnery.reload_seconds) / @as(f64, @floatFromInt(scenario.timestep_seconds)))))),
            .powder_per_round_kg = sample(scenario.seed, streams.parameters, base + 5, vessel.gunnery.powder_per_round_kg),
            .effective_range_m = sample(scenario.seed, streams.parameters, base + 6, vessel.gunnery.effective_range_m),
            .base_hit_probability = sample(scenario.seed, streams.parameters, base + 7, vessel.gunnery.hit_probability_at_reference),
            .damage_points_per_hit = sample(scenario.seed, streams.parameters, base + 8, vessel.gunnery.damage_points_per_hit),
            .crew_loss_probability = sample(scenario.seed, streams.parameters, base + 9, vessel.gunnery.crew_loss_probability_per_hit),
            .fire_probability = sample(scenario.seed, streams.parameters, base + 10, vessel.gunnery.fire_probability_per_hit),
            .flooding_probability = sample(scenario.seed, streams.parameters, base + 11, vessel.gunnery.flooding_probability_per_hit),
            .fire_suppression = sample(scenario.seed, streams.parameters, base + 12, vessel.damage_control.fire_suppression_per_step),
            .pumping = sample(scenario.seed, streams.parameters, base + 13, vessel.damage_control.pumping_per_step),
        };
        const command_payload = std.fmt.allocPrint(allocator, "vessel={s};signal={s};active_step={d};failed={any}", .{
            vessel.vessel_id, @tagName(vessel.command.signal), state.command_active_step, state.command_failed,
        }) catch return Error.OutOfMemory;
        events.append(allocator, chain.append("command_sampled", command_payload)) catch return Error.OutOfMemory;
    }

    var steps_completed: u32 = 0;
    while (steps_completed < scenario.max_steps and bothSidesActive(scenario, states)) : (steps_completed += 1) {
        @memset(pending, .{});
        const env_base = @as(u64, steps_completed) * 4;
        const wind = sample(scenario.seed, streams.environment, env_base, scenario.environment.wind_speed_mps);
        const sea = sample(scenario.seed, streams.environment, env_base + 1, scenario.environment.sea_severity);
        const visibility = sample(scenario.seed, streams.environment, env_base + 2, scenario.environment.visibility_fraction);
        const environment_payload = std.fmt.allocPrint(allocator, "step={d};wind_mps={d:.6};sea_severity={d:.6};visibility={d:.6}", .{
            steps_completed, wind, sea, visibility,
        }) catch return Error.OutOfMemory;
        events.append(allocator, chain.append("environment_sampled", environment_payload)) catch return Error.OutOfMemory;

        for (scenario.vessels, states, 0..) |vessel, *attacker, attacker_index| {
            if (attacker.status != .active or attacker.command_failed or steps_completed < attacker.command_active_step or
                steps_completed % attacker.reload_steps != 0) continue;
            const target_index = findTarget(scenario, states, vessel.side) orelse continue;
            const target = &pending[target_index];
            const powder_rounds = @floor(attacker.powder_kg / attacker.powder_per_round_kg);
            const powder_limited: u32 = if (!std.math.isFinite(powder_rounds) or powder_rounds >= std.math.maxInt(u32))
                std.math.maxInt(u32)
            else
                @intFromFloat(powder_rounds);
            const broadside: u32 = @max(1, @as(u32, vessel.gunnery.gun_count) / 2);
            const fired = @min(broadside, @min(attacker.rounds, powder_limited));
            if (fired == 0) continue;
            attacker.rounds -= fired;
            attacker.powder_kg = @max(0, attacker.powder_kg - @as(f64, @floatFromInt(fired)) * attacker.powder_per_round_kg);

            var hits: u32 = 0;
            for (0..fired) |shot_index| {
                const coordinate = (@as(u64, steps_completed) * 1_000_000) + (@as(u64, @intCast(attacker_index)) * 10_000) + shot_index;
                const range_factor = @max(0.0, 1.0 - initial_range / @max(1.0, attacker.effective_range_m));
                const weather_factor = @max(0.05, visibility * (1.0 - 0.55 * sea) * (1.0 - @min(wind / 80.0, 0.25)));
                const probability = std.math.clamp(attacker.base_hit_probability * (0.25 + 0.75 * range_factor) * weather_factor * attacker.morale * attacker.training, 0.0, 0.95);
                if (draw(scenario.seed, streams.hit, coordinate) < probability) {
                    hits += 1;
                    const severity = 0.75 + 0.5 * draw(scenario.seed, streams.damage, coordinate * 4);
                    target.hull_damage += attacker.damage_points_per_hit * severity;
                    if (draw(scenario.seed, streams.damage, coordinate * 4 + 1) < attacker.crew_loss_probability) target.crew_loss += 1;
                    if (draw(scenario.seed, streams.damage, coordinate * 4 + 2) < attacker.fire_probability) target.fire += 0.08;
                    if (draw(scenario.seed, streams.damage, coordinate * 4 + 3) < attacker.flooding_probability) target.flooding += 0.08;
                }
            }
            const payload = std.fmt.allocPrint(allocator, "step={d};attacker={s};target={s};rounds={d};hits={d}", .{
                steps_completed, vessel.vessel_id, scenario.vessels[target_index].vessel_id, fired, hits,
            }) catch return Error.OutOfMemory;
            events.append(allocator, chain.append("aggregate_volley", payload)) catch return Error.OutOfMemory;
        }

        for (scenario.vessels, states, pending) |vessel, *state, impact| {
            if (state.status != .active) continue;
            const initial_hull = vessel.damage_control.hull_integrity_points;
            const previous_status = state.status;
            state.hull = @max(0, state.hull - impact.hull_damage - state.fire * 0.7 - state.flooding * 0.5);
            state.crew -= @min(state.crew, impact.crew_loss);
            const control_fraction = if (vessel.crew.complement > 0)
                @as(f64, @floatFromInt(state.crew)) / @as(f64, @floatFromInt(vessel.crew.complement)) * state.training
            else
                0;
            state.fire = std.math.clamp(state.fire + impact.fire - state.fire_suppression * control_fraction, 0, 1.5);
            state.flooding = std.math.clamp(state.flooding + impact.flooding - state.pumping * control_fraction, 0, vessel.damage_control.flooding_capacity * 1.5);
            state.morale = std.math.clamp(state.morale - impact.hull_damage / @max(initial_hull, 1) * 0.25 - @as(f64, @floatFromInt(impact.crew_loss)) / @as(f64, @floatFromInt(vessel.crew.complement)) * 0.5 - state.fire * 0.01, 0, 1);

            if (state.hull <= 0 or state.flooding >= vessel.damage_control.flooding_capacity) {
                state.status = .sunk;
            } else if (state.morale <= vessel.crew.surrender_morale_threshold) {
                state.status = .surrendered;
            } else if (state.hull / initial_hull <= vessel.damage_control.withdrawal_hull_fraction) {
                state.status = .disengaged;
            }
            if (state.status != previous_status) {
                const payload = std.fmt.allocPrint(allocator, "step={d};vessel={s};status={s};hull={d:.6};crew={d};morale={d:.6}", .{
                    steps_completed, vessel.vessel_id, @tagName(state.status), state.hull / initial_hull, state.crew, state.morale,
                }) catch return Error.OutOfMemory;
                events.append(allocator, chain.append("vessel_status_changed", payload)) catch return Error.OutOfMemory;
            }
        }
    }

    var totals = Totals{};
    var surrendered: u32 = 0;
    var disengaged: u32 = 0;
    var sunk: u32 = 0;
    for (scenario.vessels, states, outcomes) |vessel, state, *outcome| {
        const initial_crew: u32 = vessel.crew.complement;
        const initial_rounds = vessel.gunnery.shot_rounds;
        const crew_lost = initial_crew - state.crew;
        const rounds_fired = initial_rounds - state.rounds;
        const powder_used = vessel.gunnery.powder_kg - state.powder_kg;
        outcome.* = .{
            .vessel_id = vessel.vessel_id,
            .side = vessel.side,
            .status = state.status,
            .initial_crew = initial_crew,
            .crew_remaining = state.crew,
            .crew_lost = crew_lost,
            .initial_rounds = initial_rounds,
            .rounds_fired = rounds_fired,
            .rounds_remaining = state.rounds,
            .initial_powder_kg = vessel.gunnery.powder_kg,
            .powder_used_kg = powder_used,
            .powder_remaining_kg = state.powder_kg,
            .hull_integrity_fraction = state.hull / vessel.damage_control.hull_integrity_points,
            .fire_level = state.fire,
            .flooding_level = state.flooding,
            .morale = state.morale,
        };
        totals.initial_crew += initial_crew;
        totals.crew_remaining += state.crew;
        totals.crew_lost += crew_lost;
        totals.initial_rounds += initial_rounds;
        totals.rounds_fired += rounds_fired;
        totals.rounds_remaining += state.rounds;
        totals.initial_powder += vessel.gunnery.powder_kg;
        totals.powder_used += powder_used;
        totals.powder_remaining += state.powder_kg;
        switch (state.status) {
            .surrendered => surrendered += 1,
            .disengaged => disengaged += 1,
            .sunk => sunk += 1,
            .active => {},
        }
    }

    const finish_payload = std.fmt.allocPrint(allocator, "steps={d};crew_lost={d};rounds_fired={d};surrendered={d};disengaged={d};sunk={d}", .{
        steps_completed, totals.crew_lost, totals.rounds_fired, surrendered, disengaged, sunk,
    }) catch return Error.OutOfMemory;
    events.append(allocator, chain.append("run_completed", finish_payload)) catch return Error.OutOfMemory;
    const summary: types.Summary = .{
        .scenario_sha256 = scenario_sha256,
        .scenario_id = scenario.scenario_id,
        .year = scenario.year,
        .seed = scenario.seed,
        .steps_completed = steps_completed,
        .initial_crew = totals.initial_crew,
        .crew_remaining = totals.crew_remaining,
        .crew_lost = totals.crew_lost,
        .initial_rounds = totals.initial_rounds,
        .rounds_fired = totals.rounds_fired,
        .rounds_remaining = totals.rounds_remaining,
        .initial_powder_kg = totals.initial_powder,
        .powder_used_kg = totals.powder_used,
        .powder_remaining_kg = totals.powder_remaining,
        .surrendered = surrendered,
        .disengaged = disengaged,
        .sunk = sunk,
        .conservation = .{
            .crew = totals.initial_crew == totals.crew_remaining + totals.crew_lost,
            .ammunition = totals.initial_rounds == totals.rounds_fired + totals.rounds_remaining,
            .powder = @abs(totals.initial_powder - totals.powder_used - totals.powder_remaining) <= 1e-8,
        },
        .replay_algorithm = arena.replay.algorithm_id,
        .replay_event_count = events.items.len,
        .replay_head_sha256 = chain.headHex(),
    };
    return .{ .outcomes = outcomes, .summary = summary, .replay_events = events.items };
}

fn sha256Hex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

const Totals = struct {
    initial_crew: u64 = 0,
    crew_remaining: u64 = 0,
    crew_lost: u64 = 0,
    initial_rounds: u64 = 0,
    rounds_fired: u64 = 0,
    rounds_remaining: u64 = 0,
    initial_powder: f64 = 0,
    powder_used: f64 = 0,
    powder_remaining: f64 = 0,
};

fn sample(seed: u64, stream: u8, coordinate: u64, uncertainty: types.UncertainF64) f64 {
    return uncertainty.minimum + draw(seed, stream, coordinate) * (uncertainty.maximum - uncertainty.minimum);
}

fn draw(seed: u64, stream: u8, coordinate: u64) f64 {
    return arena.counter_rng.drawUnitF64(seed, stream, coordinate);
}

fn findTarget(scenario: types.Scenario, states: []const State, side: types.Side) ?usize {
    for (scenario.vessels, states, 0..) |vessel, state, index| {
        if (vessel.side != side and state.status == .active) return index;
    }
    return null;
}

fn bothSidesActive(scenario: types.Scenario, states: []const State) bool {
    var active = [_]bool{ false, false };
    for (scenario.vessels, states) |vessel, state| {
        if (state.status == .active) active[@intFromEnum(vessel.side)] = true;
    }
    return active[0] and active[1];
}
