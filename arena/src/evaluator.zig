//! Feasibility-first screening and objective extraction.
//!
//! This module validates declarative designs and binds trusted simulation
//! results into a scorecard. It is not itself a high-fidelity voyage simulator.

const std = @import("std");
const types = @import("types.zig");
const determinism = @import("determinism.zig");

pub const Error = error{
    InvalidMission,
    InvalidSubmission,
    InvalidSimulationResult,
    MissionMismatch,
    MissionVersionMismatch,
    RulesetMismatch,
    SubmissionMismatch,
    SeedMismatch,
    DigestMismatch,
    OutOfMemory,
};

pub const ArtifactIds = struct {
    run_id: []const u8,
    mission_sha256: []const u8,
    submission_sha256: []const u8,
    simulation_result_sha256: []const u8,
};

pub fn evaluate(
    allocator: std.mem.Allocator,
    mission: types.Mission,
    submission: types.Submission,
    simulation: types.SimulationResult,
    ids: ArtifactIds,
) Error!types.Scorecard {
    try validateEnvelope(mission, submission, simulation, ids);

    var violations: std.ArrayList(types.Violation) = .empty;
    errdefer violations.deinit(allocator);
    var objectives: std.ArrayList(types.ObjectiveValue) = .empty;
    errdefer objectives.deinit(allocator);

    var total_vessels: u32 = 0;
    var total_cost_units: f64 = 0.0;
    var total_nominal_cargo_t: f64 = 0.0;

    if (submission.fleet.len == 0) {
        try addViolation(&violations, allocator, .empty_fleet, "fleet", "submission contains no vessel designs");
    }

    for (submission.fleet, 0..) |design, i| {
        for (submission.fleet[0..i]) |previous| {
            if (std.mem.eql(u8, previous.design_id, design.design_id)) {
                try addViolation(&violations, allocator, .duplicate_design_id, design.design_id, "design_id must be unique");
                break;
            }
        }

        if (design.count > std.math.maxInt(u32) - total_vessels) return Error.InvalidSubmission;
        total_vessels += design.count;

        const count: f64 = @floatFromInt(design.count);
        total_cost_units += design.unit_cost_units * count;
        total_nominal_cargo_t += design.cargo_capacity_t * count;

        try screenDesign(&violations, allocator, mission, design);
    }

    if (!std.math.isFinite(total_cost_units) or !std.math.isFinite(total_nominal_cargo_t)) {
        return Error.InvalidSubmission;
    }

    const requirements = mission.fleet_requirements;
    if (total_vessels < requirements.min_vessels) {
        try addViolation(&violations, allocator, .fleet_count_below_minimum, "fleet", "fleet has fewer vessels than the mission minimum");
    }
    if (total_vessels > requirements.max_vessels) {
        try addViolation(&violations, allocator, .fleet_count_above_maximum, "fleet", "fleet has more vessels than the mission maximum");
    }
    if (total_cost_units > requirements.max_budget_units) {
        try addViolation(&violations, allocator, .budget_exceeded, "fleet", "fleet cost exceeds the mission budget");
    }
    if (total_nominal_cargo_t < requirements.min_nominal_cargo_t) {
        try addViolation(&violations, allocator, .nominal_cargo_below_minimum, "fleet", "nominal cargo capacity is below the mission minimum");
    }

    const metrics = simulation.metrics;
    if (metrics.delivered_cargo_t < requirements.min_delivered_cargo_t) {
        try addViolation(&violations, allocator, .delivered_cargo_below_minimum, "simulation", "delivered cargo is below the mission minimum");
    }
    if (metrics.delivered_cargo_t > total_nominal_cargo_t * mission.evaluation.max_delivered_to_nominal_ratio) {
        try addViolation(&violations, allocator, .delivered_cargo_exceeds_envelope, "simulation", "delivered cargo exceeds the published mission envelope");
    }
    if (requirements.max_mean_transit_days) |limit| {
        if (metrics.mean_transit_days > limit) {
            try addViolation(&violations, allocator, .transit_time_exceeded, "simulation", "mean transit time exceeds the mission limit");
        }
    }
    if (metrics.loss_fraction > requirements.max_loss_fraction) {
        try addViolation(&violations, allocator, .loss_fraction_exceeded, "simulation", "loss fraction exceeds the mission safety limit");
    }
    if (metrics.crew_casualty_fraction > requirements.max_crew_casualty_fraction) {
        try addViolation(&violations, allocator, .crew_casualty_fraction_exceeded, "simulation", "crew casualty fraction exceeds the mission safety limit");
    }

    const feasible = violations.items.len == 0;
    if (feasible) {
        for (mission.objectives) |spec| {
            const value = try objectiveValue(spec.name, total_cost_units, metrics);
            try objectives.append(allocator, .{
                .name = spec.name,
                .direction = spec.direction,
                .aggregate = spec.aggregate,
                .epsilon = spec.epsilon,
                .value = value,
            });
        }
    }

    return .{
        .schema_version = types.scorecard_schema,
        .evaluator_version = types.evaluator_version,
        .evaluator_id = simulation.evaluator_id,
        .run_id = ids.run_id,
        .mission_id = mission.mission_id,
        .mission_version = mission.mission_version,
        .ruleset_id = mission.ruleset_id,
        .submission_id = submission.submission_id,
        .track = submission.track,
        .mission_sha256 = ids.mission_sha256,
        .submission_sha256 = ids.submission_sha256,
        .simulation_result_sha256 = ids.simulation_result_sha256,
        .backend_version = simulation.backend_version,
        .environment_sha256 = simulation.environment_sha256,
        .replay_algorithm = simulation.replay_algorithm,
        .replay_head_sha256 = simulation.replay_head_sha256,
        .replay_event_count = simulation.replay_event_count,
        .season_commitment_sha256 = simulation.season_commitment_sha256,
        .seed = simulation.seed,
        .scenario_count = simulation.scenario_count,
        .feasible = feasible,
        .total_vessels = total_vessels,
        .total_cost_units = total_cost_units,
        .total_nominal_cargo_t = total_nominal_cargo_t,
        .violations = try violations.toOwnedSlice(allocator),
        .objectives = try objectives.toOwnedSlice(allocator),
    };
}

pub fn deinitScorecard(allocator: std.mem.Allocator, scorecard: *types.Scorecard) void {
    allocator.free(scorecard.violations);
    allocator.free(scorecard.objectives);
    scorecard.* = undefined;
}

fn validateEnvelope(
    mission: types.Mission,
    submission: types.Submission,
    simulation: types.SimulationResult,
    ids: ArtifactIds,
) Error!void {
    if (!std.mem.eql(u8, mission.schema_version, types.mission_schema)) return Error.InvalidMission;
    if (!std.mem.eql(u8, submission.schema_version, types.submission_schema)) return Error.InvalidSubmission;
    if (!std.mem.eql(u8, simulation.schema_version, types.simulation_result_schema)) return Error.InvalidSimulationResult;
    if (mission.mission_id.len == 0 or mission.mission_version.len == 0 or mission.ruleset_id.len == 0) return Error.InvalidMission;
    if (submission.submission_id.len == 0) return Error.InvalidSubmission;
    if (!std.mem.eql(u8, mission.rng.algorithm, determinism.algorithm_id)) return Error.InvalidMission;
    if (mission.rng.streams.len == 0 or mission.rng.public_seeds.len == 0) return Error.InvalidMission;
    if (mission.objectives.len == 0 or mission.sources.len == 0 or
        mission.allowed_materials.len == 0 or mission.allowed_propulsion.len == 0 or
        mission.allowed_hull_forms.len == 0)
    {
        return Error.InvalidMission;
    }
    if (!std.mem.eql(u8, mission.evaluation.ranking, "epsilon_pareto_v1")) return Error.InvalidMission;
    if (mission.fleet_requirements.min_vessels > mission.fleet_requirements.max_vessels) return Error.InvalidMission;
    if (mission.era.start_year > mission.era.end_year or !validNonNegative(mission.route.nominal_distance_nm) or mission.route.nominal_distance_nm == 0.0) return Error.InvalidMission;
    if (!validSha256Hex(mission.rng.hidden_seed_commitment_sha256) or
        !validSha256Hex(ids.run_id) or !validSha256Hex(ids.mission_sha256) or !validSha256Hex(ids.submission_sha256) or
        !validSha256Hex(ids.simulation_result_sha256))
    {
        return Error.InvalidMission;
    }
    if (simulation.backend_version.len == 0 or simulation.replay_algorithm.len == 0 or
        simulation.replay_event_count == 0 or !validSha256Hex(simulation.environment_sha256) or
        !validSha256Hex(simulation.replay_head_sha256) or
        !validSha256Hex(simulation.season_commitment_sha256)) return Error.InvalidSimulationResult;
    if (!std.mem.eql(u8, simulation.season_commitment_sha256, mission.rng.hidden_seed_commitment_sha256))
        return Error.InvalidSimulationResult;
    if (mission.design_bounds.max_displacement_error_fraction < 0.0 or mission.design_bounds.max_displacement_error_fraction > 1.0) return Error.InvalidMission;
    if (!validBounds(mission.design_bounds)) return Error.InvalidMission;
    if (!validRequirements(mission.fleet_requirements)) return Error.InvalidMission;
    if (mission.evaluation.min_scenarios == 0 or simulation.scenario_count < mission.evaluation.min_scenarios) return Error.InvalidSimulationResult;

    for (mission.objectives, 0..) |objective, i| {
        if (!validNonNegative(objective.epsilon)) return Error.InvalidMission;
        if (objective.direction != canonicalDirection(objective.name)) return Error.InvalidMission;
        for (mission.objectives[0..i]) |previous| if (previous.name == objective.name) return Error.InvalidMission;
    }
    if (hasDuplicates(types.RngStream, mission.rng.streams) or
        hasDuplicates(u64, mission.rng.public_seeds) or
        hasDuplicates(types.Material, mission.allowed_materials) or
        hasDuplicates(types.Propulsion, mission.allowed_propulsion) or
        hasDuplicates(types.HullForm, mission.allowed_hull_forms)) return Error.InvalidMission;

    if (!std.mem.eql(u8, mission.mission_id, submission.mission_id) or
        !std.mem.eql(u8, mission.mission_id, simulation.mission_id)) return Error.MissionMismatch;
    if (!std.mem.eql(u8, mission.mission_version, submission.mission_version) or
        !std.mem.eql(u8, mission.mission_version, simulation.mission_version)) return Error.MissionVersionMismatch;
    if (!std.mem.eql(u8, mission.ruleset_id, submission.ruleset_id)) return Error.RulesetMismatch;
    if (!std.mem.eql(u8, submission.submission_id, simulation.submission_id)) return Error.SubmissionMismatch;
    if (!contains(u64, mission.rng.public_seeds, simulation.seed)) return Error.SeedMismatch;
    if (!std.mem.eql(u8, simulation.mission_sha256, ids.mission_sha256) or
        !std.mem.eql(u8, simulation.submission_sha256, ids.submission_sha256)) return Error.DigestMismatch;

    const metrics = simulation.metrics;
    if (!validNonNegative(metrics.delivered_cargo_t) or
        !validNonNegative(metrics.mean_transit_days) or
        !validNonNegative(metrics.p95_transit_days) or
        !std.math.isFinite(metrics.loss_fraction) or metrics.loss_fraction < 0.0 or metrics.loss_fraction > 1.0)
    {
        return Error.InvalidSimulationResult;
    }
    if (!std.math.isFinite(metrics.crew_casualty_fraction) or
        metrics.crew_casualty_fraction < 0.0 or metrics.crew_casualty_fraction > 1.0)
    {
        return Error.InvalidSimulationResult;
    }
    if (metrics.crew_exposure_days) |value| if (!validNonNegative(value)) return Error.InvalidSimulationResult;
    if (metrics.emissions_t_co2e) |value| if (!validNonNegative(value)) return Error.InvalidSimulationResult;
    if (metrics.required_freight_rate_units_per_t) |value| if (!validNonNegative(value)) return Error.InvalidSimulationResult;
}

fn screenDesign(
    violations: *std.ArrayList(types.Violation),
    allocator: std.mem.Allocator,
    mission: types.Mission,
    design: types.VesselDesign,
) Error!void {
    const subject = if (design.design_id.len == 0) "unnamed-design" else design.design_id;
    const numeric = [_]f64{
        design.length_m,
        design.beam_m,
        design.draft_m,
        design.block_coefficient,
        design.displacement_t,
        design.cargo_capacity_t,
        design.sail_area_m2,
        design.unit_cost_units,
    };
    for (numeric) |value| {
        if (!validNonNegative(value)) {
            try addViolation(violations, allocator, .invalid_numeric_value, subject, "design values must be finite and non-negative");
            return;
        }
    }
    if (design.count == 0 or design.length_m == 0.0 or design.beam_m == 0.0 or
        design.draft_m == 0.0 or design.displacement_t == 0.0 or design.unit_cost_units == 0.0)
    {
        try addViolation(violations, allocator, .invalid_numeric_value, subject, "count and principal design values must be greater than zero");
        return;
    }

    const bounds = mission.design_bounds;
    if (!inRange(design.length_m, bounds.min_length_m, bounds.max_length_m) or
        !inRange(design.beam_m, bounds.min_beam_m, bounds.max_beam_m) or
        !inRange(design.draft_m, bounds.min_draft_m, bounds.max_draft_m) or
        !inRange(design.displacement_t, bounds.min_displacement_t, bounds.max_displacement_t) or
        !inRange(design.block_coefficient, bounds.min_block_coefficient, bounds.max_block_coefficient))
    {
        try addViolation(violations, allocator, .dimension_out_of_bounds, subject, "principal dimensions or block coefficient are outside mission bounds");
    }

    const length_beam = design.length_m / design.beam_m;
    const beam_draft = design.beam_m / design.draft_m;
    if (!inRange(length_beam, bounds.min_length_beam_ratio, bounds.max_length_beam_ratio) or
        !inRange(beam_draft, bounds.min_beam_draft_ratio, bounds.max_beam_draft_ratio))
    {
        try addViolation(violations, allocator, .ratio_out_of_bounds, subject, "L/B or B/T is outside mission bounds");
    }

    const expected_displacement_t = 1.025 * design.length_m * design.beam_m * design.draft_m * design.block_coefficient;
    const displacement_error = @abs(design.displacement_t - expected_displacement_t) / expected_displacement_t;
    if (displacement_error > bounds.max_displacement_error_fraction) {
        try addViolation(violations, allocator, .displacement_mismatch, subject, "declared displacement does not close against L*B*T*Cb at seawater density");
    }

    if (!contains(types.Material, mission.allowed_materials, design.material)) {
        try addViolation(violations, allocator, .material_not_allowed, subject, "material is unavailable in this era pack");
    }
    if (!contains(types.Propulsion, mission.allowed_propulsion, design.propulsion)) {
        try addViolation(violations, allocator, .propulsion_not_allowed, subject, "propulsion is unavailable in this era pack");
    }
    if (!contains(types.HullForm, mission.allowed_hull_forms, design.hull_form)) {
        try addViolation(violations, allocator, .hull_form_not_allowed, subject, "hull form is unavailable in this era pack");
    }
    if ((design.propulsion == .sail or design.propulsion == .sail_and_oar) and design.sail_area_m2 <= 0.0) {
        try addViolation(violations, allocator, .sail_area_required, subject, "sail propulsion requires positive sail area");
    }
    if (design.crew < bounds.min_crew_per_vessel or design.crew > bounds.max_crew_per_vessel) {
        try addViolation(violations, allocator, .crew_out_of_bounds, subject, "crew is outside the mission envelope");
    }
}

fn objectiveValue(name: types.ObjectiveName, total_cost_units: f64, metrics: types.SimulationMetrics) Error!f64 {
    return switch (name) {
        .delivered_cargo_t => metrics.delivered_cargo_t,
        .mean_transit_days => metrics.mean_transit_days,
        .p95_transit_days => metrics.p95_transit_days,
        .total_cost_units => total_cost_units,
        .loss_fraction => metrics.loss_fraction,
        .crew_casualty_fraction => metrics.crew_casualty_fraction,
        .crew_exposure_days => metrics.crew_exposure_days orelse return Error.InvalidSimulationResult,
        .emissions_t_co2e => metrics.emissions_t_co2e orelse return Error.InvalidSimulationResult,
        .required_freight_rate_units_per_t => metrics.required_freight_rate_units_per_t orelse return Error.InvalidSimulationResult,
    };
}

pub fn canonicalDirection(name: types.ObjectiveName) types.Direction {
    return switch (name) {
        .delivered_cargo_t => .maximize,
        .mean_transit_days,
        .p95_transit_days,
        .total_cost_units,
        .loss_fraction,
        .crew_casualty_fraction,
        .crew_exposure_days,
        .emissions_t_co2e,
        .required_freight_rate_units_per_t,
        => .minimize,
    };
}

fn addViolation(
    violations: *std.ArrayList(types.Violation),
    allocator: std.mem.Allocator,
    code: types.ViolationCode,
    subject: []const u8,
    detail: []const u8,
) Error!void {
    try violations.append(allocator, .{ .code = code, .subject = subject, .detail = detail });
}

fn contains(comptime T: type, haystack: []const T, needle: T) bool {
    for (haystack) |item| if (item == needle) return true;
    return false;
}

fn hasDuplicates(comptime T: type, values: []const T) bool {
    for (values, 0..) |value, i| {
        for (values[0..i]) |previous| if (previous == value) return true;
    }
    return false;
}

fn validSha256Hex(value: []const u8) bool {
    if (value.len != 64) return false;
    for (value) |byte| {
        if (!((byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f'))) return false;
    }
    return true;
}

fn validBounds(bounds: types.DesignBounds) bool {
    const pairs = [_][2]f64{
        .{ bounds.min_length_m, bounds.max_length_m },
        .{ bounds.min_beam_m, bounds.max_beam_m },
        .{ bounds.min_draft_m, bounds.max_draft_m },
        .{ bounds.min_displacement_t, bounds.max_displacement_t },
        .{ bounds.min_block_coefficient, bounds.max_block_coefficient },
        .{ bounds.min_length_beam_ratio, bounds.max_length_beam_ratio },
        .{ bounds.min_beam_draft_ratio, bounds.max_beam_draft_ratio },
    };
    for (pairs) |pair| {
        if (!validNonNegative(pair[0]) or !validNonNegative(pair[1]) or pair[0] > pair[1]) return false;
    }
    return bounds.min_crew_per_vessel <= bounds.max_crew_per_vessel;
}

fn validRequirements(requirements: types.FleetRequirements) bool {
    const values = [_]f64{
        requirements.min_nominal_cargo_t,
        requirements.min_delivered_cargo_t,
        requirements.max_budget_units,
        requirements.max_loss_fraction,
        requirements.max_crew_casualty_fraction,
    };
    for (values) |value| if (!validNonNegative(value)) return false;
    if (requirements.max_loss_fraction > 1.0 or requirements.max_crew_casualty_fraction > 1.0) return false;
    if (requirements.max_mean_transit_days) |value| if (!validNonNegative(value)) return false;
    return true;
}

fn validNonNegative(value: f64) bool {
    return std.math.isFinite(value) and value >= 0.0 and !(value == 0.0 and std.math.signbit(value));
}

fn inRange(value: f64, minimum: f64, maximum: f64) bool {
    return value >= minimum and value <= maximum;
}

fn testMission() types.Mission {
    const waypoints = [_][]const u8{"Cape"};
    const streams = [_]types.RngStream{ .weather, .demand, .damage, .traffic };
    const seeds = [_]u64{11};
    const materials = [_]types.Material{.oak};
    const propulsion = [_]types.Propulsion{.sail};
    const hull_forms = [_]types.HullForm{.monohull};
    const objectives = [_]types.ObjectiveSpec{
        .{ .name = .delivered_cargo_t, .direction = .maximize, .aggregate = .mean, .epsilon = 0.1 },
        .{ .name = .mean_transit_days, .direction = .minimize, .aggregate = .mean, .epsilon = 0.1 },
        .{ .name = .total_cost_units, .direction = .minimize, .aggregate = .fixed, .epsilon = 1.0 },
    };
    const sources = [_]types.SourceRef{.{
        .source_id = "source",
        .title = "Source",
        .url = "https://example.invalid",
        .license = "OGL",
        .note = "fixture",
    }};
    return .{
        .schema_version = types.mission_schema,
        .mission_id = "mission",
        .mission_version = "v0",
        .ruleset_id = "rules-v0",
        .title = "Fixture",
        .summary = "Fixture",
        .currency_unit = "credits",
        .era = .{ .label = "fixture", .start_year = 1700, .end_year = 1701, .mode = .era_constrained_counterfactual },
        .route = .{ .origin = "A", .destination = "B", .waypoints = &waypoints, .nominal_distance_nm = 100.0 },
        .rng = .{
            .algorithm = determinism.algorithm_id,
            .streams = &streams,
            .public_seeds = &seeds,
            .hidden_seed_commitment_sha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        },
        .fleet_requirements = .{
            .min_vessels = 1,
            .max_vessels = 4,
            .min_nominal_cargo_t = 100.0,
            .min_delivered_cargo_t = 90.0,
            .max_budget_units = 1000.0,
            .max_mean_transit_days = 200.0,
            .max_loss_fraction = 0.2,
            .max_crew_casualty_fraction = 0.05,
        },
        .design_bounds = .{
            .min_length_m = 20.0,
            .max_length_m = 60.0,
            .min_beam_m = 5.0,
            .max_beam_m = 15.0,
            .min_draft_m = 2.0,
            .max_draft_m = 8.0,
            .min_displacement_t = 100.0,
            .max_displacement_t = 2000.0,
            .min_block_coefficient = 0.4,
            .max_block_coefficient = 0.8,
            .min_length_beam_ratio = 2.5,
            .max_length_beam_ratio = 6.0,
            .min_beam_draft_ratio = 1.2,
            .max_beam_draft_ratio = 4.0,
            .min_crew_per_vessel = 1,
            .max_crew_per_vessel = 200,
            .max_displacement_error_fraction = 0.02,
        },
        .evaluation = .{ .min_scenarios = 4, .max_delivered_to_nominal_ratio = 1.0, .ranking = "epsilon_pareto_v1" },
        .allowed_materials = &materials,
        .allowed_propulsion = &propulsion,
        .allowed_hull_forms = &hull_forms,
        .objectives = &objectives,
        .sources = &sources,
    };
}

fn testSubmission() types.Submission {
    const fleet = [_]types.VesselDesign{.{
        .design_id = "ship",
        .class_name = "Merchant",
        .count = 1,
        .hull_form = .monohull,
        .material = .oak,
        .propulsion = .sail,
        .length_m = 30.0,
        .beam_m = 8.0,
        .draft_m = 4.0,
        .block_coefficient = 0.6,
        .displacement_t = 590.4,
        .cargo_capacity_t = 120.0,
        .sail_area_m2 = 500.0,
        .crew = 40,
        .unit_cost_units = 500.0,
    }};
    return .{
        .schema_version = types.submission_schema,
        .submission_id = "entry",
        .mission_id = "mission",
        .mission_version = "v0",
        .ruleset_id = "rules-v0",
        .track = .human_ai,
        .entrant = "fixture",
        .provenance = .{ .yard_revision = "abc", .zig_version = "0.16.0", .authoring_system = "test" },
        .fleet = &fleet,
    };
}

fn testSimulation() types.SimulationResult {
    return .{
        .schema_version = types.simulation_result_schema,
        .evaluator_id = "fixture-backend",
        .mission_id = "mission",
        .mission_version = "v0",
        .submission_id = "entry",
        .mission_sha256 = test_ids.mission_sha256,
        .submission_sha256 = test_ids.submission_sha256,
        .backend_version = "fixture-backend-v1",
        .environment_sha256 = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        .replay_algorithm = "sha256-chain-v1",
        .replay_head_sha256 = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        .replay_event_count = 1,
        .season_commitment_sha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        .seed = 11,
        .scenario_count = 4,
        .metrics = .{
            .delivered_cargo_t = 100.0,
            .mean_transit_days = 120.0,
            .p95_transit_days = 150.0,
            .loss_fraction = 0.05,
            .crew_casualty_fraction = 0.01,
        },
    };
}

const test_ids: ArtifactIds = .{
    .run_id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    .mission_sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    .submission_sha256 = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    .simulation_result_sha256 = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
};

test "feasible submission receives objective vector" {
    var scorecard = try evaluate(std.testing.allocator, testMission(), testSubmission(), testSimulation(), test_ids);
    defer deinitScorecard(std.testing.allocator, &scorecard);
    try std.testing.expect(scorecard.feasible);
    try std.testing.expectEqual(@as(usize, 0), scorecard.violations.len);
    try std.testing.expectEqual(@as(usize, 3), scorecard.objectives.len);
}

test "infeasible submission receives no objective vector" {
    var submission = testSubmission();
    var fleet = [_]types.VesselDesign{submission.fleet[0]};
    fleet[0].material = .steel;
    submission.fleet = &fleet;
    var scorecard = try evaluate(std.testing.allocator, testMission(), submission, testSimulation(), test_ids);
    defer deinitScorecard(std.testing.allocator, &scorecard);
    try std.testing.expect(!scorecard.feasible);
    try std.testing.expectEqual(@as(usize, 0), scorecard.objectives.len);
    try std.testing.expect(scorecard.violations.len > 0);
}

test "displacement closure is a hard feasibility gate" {
    var submission = testSubmission();
    var fleet = [_]types.VesselDesign{submission.fleet[0]};
    fleet[0].displacement_t = 300.0;
    submission.fleet = &fleet;
    var scorecard = try evaluate(std.testing.allocator, testMission(), submission, testSimulation(), test_ids);
    defer deinitScorecard(std.testing.allocator, &scorecard);
    try std.testing.expect(!scorecard.feasible);
    var found = false;
    for (scorecard.violations) |violation| {
        if (violation.code == .displacement_mismatch) found = true;
    }
    try std.testing.expect(found);
}

test "forged artifact binding fails closed" {
    var simulation = testSimulation();
    simulation.submission_sha256 = "forged";
    try std.testing.expectError(Error.DigestMismatch, evaluate(std.testing.allocator, testMission(), testSubmission(), simulation, test_ids));
}

test "non-finite simulation metrics fail closed" {
    var simulation = testSimulation();
    simulation.metrics.mean_transit_days = std.math.nan(f64);
    try std.testing.expectError(Error.InvalidSimulationResult, evaluate(std.testing.allocator, testMission(), testSubmission(), simulation, test_ids));
}

test "negative zero simulation metrics fail closed" {
    var simulation = testSimulation();
    simulation.metrics.mean_transit_days = -0.0;
    try std.testing.expectError(Error.InvalidSimulationResult, evaluate(std.testing.allocator, testMission(), testSubmission(), simulation, test_ids));
}
