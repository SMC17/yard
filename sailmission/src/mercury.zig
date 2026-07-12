//! Official Mercury fleet backend: era gates + sail physics + economics.

const std = @import("std");
const arena = @import("yard_arena");
const econ = @import("yard_econ");
const spec = @import("spec.zig");
const physics = @import("physics.zig");
const gates = @import("gates.zig");
const voyage = @import("voyage.zig");
const historical_env = @import("historical_env.zig");

pub const schema_id = "yard.arena.mercury-backend.v0";
pub const backend_version = "yard-mercury-empirical-sail-v0.1.0";
pub const evaluator_id = "yard-mercury-official-v0";

pub const Economics = struct {
    interest_rate: f64,
    life_years: u32,
    crew_cost_units_per_person_year: f64,
    maintenance_fraction: f64,
    insurance_fraction: f64,
    port_cost_units_per_voyage: f64,
    turnaround_days: f64,
    operating_days_per_year: f64,
};

pub const BackendConfig = struct {
    schema_version: []const u8,
    backend_version: []const u8,
    scenario_count: u32,
    start_month: u8,
    segment_nm: f64,
    becalmed_floor_mps: f64,
    storm_threshold_mps: f64,
    storm_loss_probability: f64,
    storm_severity_exponent: f64,
    max_segment_loss_probability: f64,
    max_transit_days: f64,
    min_gm_m: f64,
    gate_wind_mps: f64,
    max_heel_deg: f64,
    require_is_code: bool,
    economics: Economics,
};

pub const Error = error{
    InvalidConfig,
    InvalidMission,
    InvalidSubmission,
    InvalidEnvironment,
    DesignGateFailed,
    UnknownMaterial,
    OutOfMemory,
};

pub const Run = struct {
    simulation: arena.types.SimulationResult,
    replay_events: []const arena.replay.OwnedEvent,
};

const ClassModel = struct {
    design: arena.types.VesselDesign,
    ship: spec.Submission,
    grid: voyage.SpeedGrid,
    gm_m: f64,
};

const ClassAccumulator = struct {
    days_survived_sum: f64 = 0,
    survived: u64 = 0,
    losses: u64 = 0,
};

const Outcome = struct {
    lost: bool,
    days: f64,
    cargo_t: f64,
    crew_lost: u32,
    weather_trace_sha256: [64]u8,
};

pub fn parseConfig(allocator: std.mem.Allocator, json: []const u8) Error!std.json.Parsed(BackendConfig) {
    const parsed = std.json.parseFromSlice(BackendConfig, allocator, json, .{}) catch |err| switch (err) {
        error.OutOfMemory => return Error.OutOfMemory,
        else => return Error.InvalidConfig,
    };
    errdefer parsed.deinit();
    try validateConfig(parsed.value);
    return parsed;
}

pub fn evaluate(
    allocator: std.mem.Allocator,
    mission: arena.types.Mission,
    submission: arena.types.Submission,
    environment: historical_env.Environment,
    config: BackendConfig,
    mission_sha256: []const u8,
    submission_sha256: []const u8,
    environment_sha256: []const u8,
    seed: u64,
) Error!Run {
    try validateConfig(config);
    historical_env.validate(environment) catch return Error.InvalidEnvironment;
    if (!std.mem.eql(u8, mission.mission_id, "mercury-1778-outbound") or
        !std.mem.eql(u8, mission.mission_id, submission.mission_id) or
        submission.fleet.len == 0 or !containsSeed(mission.rng.public_seeds, seed) or
        config.scenario_count < mission.evaluation.min_scenarios)
        return Error.InvalidMission;
    if (mission_sha256.len != 64 or submission_sha256.len != 64 or environment_sha256.len != 64)
        return Error.InvalidSubmission;

    var models = try allocator.alloc(ClassModel, submission.fleet.len);
    var accumulators = try allocator.alloc(ClassAccumulator, submission.fleet.len);
    @memset(accumulators, .{});
    const gate_mission = gateMission(config);
    var total_vessels: u32 = 0;
    var total_crew_per_scenario: u64 = 0;
    for (submission.fleet, 0..) |design, index| {
        if (design.count == 0 or design.propulsion != .sail or design.hull_form != .monohull)
            return Error.InvalidSubmission;
        const ship = try mapDesign(design);
        const gate = gates.evaluate(allocator, gate_mission, ship) catch |err| switch (err) {
            error.OutOfMemory => return Error.OutOfMemory,
            error.UnknownMaterial => return Error.UnknownMaterial,
            error.UnknownEra => return Error.InvalidConfig,
        };
        if (!gate.all_pass) return Error.DesignGateFailed;
        const table = physics.resistanceTable(ship.hull);
        models[index] = .{
            .design = design,
            .ship = ship,
            .grid = voyage.SpeedGrid.build(physics.rigKind(ship.rig), .{ .draft_m = ship.hull.draft_m }, &table),
            .gm_m = gate.gm_corrected_m,
        };
        total_vessels = std.math.add(u32, total_vessels, design.count) catch return Error.InvalidSubmission;
        total_crew_per_scenario += @as(u64, design.crew) * design.count;
    }
    if (total_vessels == 0 or total_crew_per_scenario == 0) return Error.InvalidSubmission;

    var chain: arena.replay.Chain = .{};
    var replay_events: std.ArrayList(arena.replay.OwnedEvent) = .empty;
    const start_payload = try std.fmt.allocPrint(
        allocator,
        "mission={s};submission={s};seed={d};scenarios={d};environment={s};dataset={s}",
        .{ mission.mission_id, submission.submission_id, seed, config.scenario_count, environment_sha256, environment.dataset_id },
    );
    try replay_events.append(allocator, chain.append("run_started", start_payload));

    var scenario_days = try allocator.alloc(f64, config.scenario_count);
    var delivered_sum: f64 = 0;
    var transit_sum: f64 = 0;
    var crew_exposure_sum: f64 = 0;
    var total_losses: u64 = 0;
    var total_crew_lost: u64 = 0;

    for (0..config.scenario_count) |scenario_index_usize| {
        const scenario_index: u32 = @intCast(scenario_index_usize);
        var vessel_global: u32 = 0;
        var scenario_delivered: f64 = 0;
        var scenario_completion_days: f64 = 0;
        var scenario_survivors: u32 = 0;
        for (models, 0..) |*model, class_index| {
            for (0..model.design.count) |_| {
                const outcome = try simulateVessel(
                    environment,
                    config,
                    model,
                    seed,
                    scenario_index,
                    vessel_global,
                );
                if (outcome.lost) {
                    total_losses += 1;
                    total_crew_lost += outcome.crew_lost;
                    accumulators[class_index].losses += 1;
                } else {
                    scenario_delivered += outcome.cargo_t;
                    scenario_completion_days = @max(scenario_completion_days, outcome.days);
                    scenario_survivors += 1;
                    accumulators[class_index].days_survived_sum += outcome.days;
                    accumulators[class_index].survived += 1;
                }
                crew_exposure_sum += @as(f64, @floatFromInt(model.design.crew)) * outcome.days;
                const payload = try std.fmt.allocPrint(
                    allocator,
                    "scenario={d};vessel={d};design={s};lost={};days={d:.9};cargo_t={d:.6};crew_lost={d};weather={s}",
                    .{ scenario_index, vessel_global, model.design.design_id, outcome.lost, outcome.days, outcome.cargo_t, outcome.crew_lost, &outcome.weather_trace_sha256 },
                );
                try replay_events.append(allocator, chain.append("vessel_completed", payload));
                vessel_global += 1;
            }
        }
        if (scenario_survivors == 0) scenario_completion_days = config.max_transit_days;
        scenario_days[scenario_index_usize] = scenario_completion_days;
        delivered_sum += scenario_delivered;
        transit_sum += scenario_completion_days;
    }

    std.mem.sort(f64, scenario_days, {}, std.sort.asc(f64));
    const scenario_count_f: f64 = @floatFromInt(config.scenario_count);
    const vessel_trials: f64 = @as(f64, @floatFromInt(total_vessels)) * scenario_count_f;
    const crew_trials: f64 = @as(f64, @floatFromInt(total_crew_per_scenario)) * scenario_count_f;
    const p95_index = @min(scenario_days.len - 1, (scenario_days.len * 95 + 99) / 100 - 1);
    const required_freight_rate = fleetRequiredFreightRate(models, accumulators, config);
    const metrics: arena.types.SimulationMetrics = .{
        .delivered_cargo_t = delivered_sum / scenario_count_f,
        .mean_transit_days = transit_sum / scenario_count_f,
        .p95_transit_days = scenario_days[p95_index],
        .loss_fraction = @as(f64, @floatFromInt(total_losses)) / vessel_trials,
        .crew_casualty_fraction = @as(f64, @floatFromInt(total_crew_lost)) / crew_trials,
        .crew_exposure_days = crew_exposure_sum / scenario_count_f,
        .emissions_t_co2e = 0,
        .required_freight_rate_units_per_t = required_freight_rate,
    };

    const finish_payload = try std.fmt.allocPrint(
        allocator,
        "delivered_cargo_t={d:.6};mean_transit_days={d:.9};p95_transit_days={d:.9};loss_fraction={d:.9};crew_casualty_fraction={d:.9};rfr={d:.9}",
        .{ metrics.delivered_cargo_t, metrics.mean_transit_days, metrics.p95_transit_days, metrics.loss_fraction, metrics.crew_casualty_fraction, required_freight_rate },
    );
    try replay_events.append(allocator, chain.append("run_completed", finish_payload));
    const replay_head = chain.headHex();
    const replay_head_owned = try allocator.dupe(u8, &replay_head);

    return .{
        .simulation = .{
            .schema_version = arena.types.simulation_result_schema,
            .evaluator_id = evaluator_id,
            .mission_id = mission.mission_id,
            .mission_version = mission.mission_version,
            .submission_id = submission.submission_id,
            .mission_sha256 = mission_sha256,
            .submission_sha256 = submission_sha256,
            .backend_version = backend_version,
            .environment_sha256 = environment_sha256,
            .replay_algorithm = arena.replay.algorithm_id,
            .replay_head_sha256 = replay_head_owned,
            .replay_event_count = replay_events.items.len,
            .season_commitment_sha256 = mission.rng.hidden_seed_commitment_sha256,
            .seed = seed,
            .scenario_count = config.scenario_count,
            .metrics = metrics,
        },
        .replay_events = try replay_events.toOwnedSlice(allocator),
    };
}

fn validateConfig(config: BackendConfig) Error!void {
    const finite_positive = [_]f64{
        config.segment_nm,
        config.becalmed_floor_mps,
        config.storm_threshold_mps,
        config.storm_severity_exponent,
        config.max_transit_days,
        config.gate_wind_mps,
        config.max_heel_deg,
        config.economics.turnaround_days,
        config.economics.operating_days_per_year,
    };
    if (!std.mem.eql(u8, config.schema_version, schema_id) or
        !std.mem.eql(u8, config.backend_version, backend_version) or config.scenario_count == 0 or
        config.start_month < 1 or config.start_month > 12) return Error.InvalidConfig;
    for (finite_positive) |value| if (!std.math.isFinite(value) or value <= 0) return Error.InvalidConfig;
    if (!fraction(config.storm_loss_probability) or !fraction(config.max_segment_loss_probability) or
        config.economics.life_years == 0 or config.min_gm_m < 0 or
        config.economics.interest_rate < 0 or config.economics.maintenance_fraction < 0 or
        config.economics.insurance_fraction < 0 or config.economics.crew_cost_units_per_person_year < 0 or
        config.economics.port_cost_units_per_voyage < 0) return Error.InvalidConfig;
}

fn gateMission(config: BackendConfig) spec.MissionSpec {
    return .{
        .schema = spec.mission_schema_id,
        .id = "mercury-gate",
        .era_id = "age_of_sail",
        .waypoints = &.{},
        .legs = &.{},
        .monte_carlo = .{ .runs = 1, .base_seed = 0 },
        .gates = .{
            .min_gm_m = config.min_gm_m,
            .require_is_code = config.require_is_code,
            .gate_wind_mps = config.gate_wind_mps,
            .max_heel_deg = config.max_heel_deg,
        },
        .objectives = &.{},
    };
}

fn mapDesign(design: arena.types.VesselDesign) Error!spec.Submission {
    const material = switch (design.material) {
        .oak => "oak",
        .teak => "teak",
        .softwood => "softwood",
        else => return Error.UnknownMaterial,
    };
    const depth = design.depth_m orelse design.draft_m * 1.65;
    const kg = design.kg_m orelse depth * 0.48;
    const wetted = design.wetted_surface_m2 orelse
        0.9 * design.length_m * (2.0 * design.draft_m + design.beam_m) * @sqrt(design.block_coefficient);
    const cr = design.residuary_coefficient orelse
        (0.0013 + 0.0035 * @max(0.0, design.block_coefficient - 0.45));
    return .{
        .schema = spec.submission_schema_id,
        .id = design.design_id,
        .author = "arena-adapter",
        .material = material,
        .hull = .{
            .loa_m = design.length_m,
            .beam_m = design.beam_m,
            .draft_m = design.draft_m,
            .depth_m = depth,
            .cb = design.block_coefficient,
            .displacement_m3 = design.displacement_t / 1.025,
            .wetted_surface_m2 = wetted,
            .kg_m = kg,
            .cr = cr,
            .form_factor = design.form_factor orelse 1.22,
        },
        .rig = .{
            .kind = .square,
            .area_m2 = design.sail_area_m2,
            .min_brace_deg = design.min_brace_deg orelse 32.0,
        },
    };
}

fn simulateVessel(
    environment: historical_env.Environment,
    config: BackendConfig,
    model: *const ClassModel,
    seed: u64,
    scenario: u32,
    vessel_index: u32,
) Error!Outcome {
    var total_hours: f64 = 0;
    var global_segment: u32 = 0;
    var weather_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (environment.legs, 0..) |leg, leg_index| {
        const distance_nm = historical_env.legDistanceNm(leg) catch return Error.InvalidEnvironment;
        const segments: u32 = @intFromFloat(@ceil(distance_nm / config.segment_nm));
        const segment_nm = distance_nm / @as(f64, @floatFromInt(segments));
        for (0..segments) |_| {
            const elapsed_months: u32 = @intFromFloat(@floor(total_hours / (24.0 * 30.4375)));
            const month: u8 = @intCast(((@as(u32, config.start_month) - 1 + elapsed_months) % 12) + 1);
            const weather_coordinate = (@as(u64, scenario) << 32) | global_segment;
            const draw_base = weather_coordinate * 4;
            const sample = historical_env.sample(
                environment,
                leg_index,
                month,
                arena.counter_rng.drawUnitF64(seed, @intFromEnum(arena.types.RngStream.weather), draw_base),
                arena.counter_rng.drawUnitF64(seed, @intFromEnum(arena.types.RngStream.weather), draw_base + 1),
                arena.counter_rng.drawUnitF64(seed, @intFromEnum(arena.types.RngStream.weather), draw_base + 2),
            ) catch return Error.InvalidEnvironment;
            var trace_bytes: [20]u8 = undefined;
            std.mem.writeInt(u32, trace_bytes[0..4], @intCast(leg_index), .little);
            std.mem.writeInt(u32, trace_bytes[4..8], global_segment, .little);
            std.mem.writeInt(u32, trace_bytes[8..12], @intCast(sample.speed_bin), .little);
            std.mem.writeInt(u32, trace_bytes[12..16], @intCast(sample.angle_bin), .little);
            std.mem.writeInt(u32, trace_bytes[16..20], sample.observation_count, .little);
            weather_hasher.update(&trace_bytes);

            if (sample.wind_speed_mps >= config.storm_threshold_mps) {
                const severity = std.math.pow(
                    f64,
                    sample.wind_speed_mps / config.storm_threshold_mps,
                    config.storm_severity_exponent,
                );
                const stability_factor = @min(2.0, @max(0.5, config.min_gm_m / model.gm_m));
                const probability = @min(config.max_segment_loss_probability, config.storm_loss_probability * severity * stability_factor);
                const damage_coordinate = (@as(u64, scenario) << 32) |
                    (@as(u64, vessel_index) << 16) | global_segment;
                if (arena.counter_rng.drawUnitF64(seed, @intFromEnum(arena.types.RngStream.damage), damage_coordinate) < probability) {
                    var weather_digest: [32]u8 = undefined;
                    weather_hasher.final(&weather_digest);
                    return .{
                        .lost = true,
                        .days = total_hours / 24.0,
                        .cargo_t = 0,
                        .crew_lost = model.design.crew,
                        .weather_trace_sha256 = std.fmt.bytesToHex(weather_digest, .lower),
                    };
                }
            }
            const speed = @max(
                model.grid.madeGood(sample.wind_speed_mps, sample.relative_wind_angle_deg),
                config.becalmed_floor_mps,
            );
            total_hours += segment_nm * 1852.0 / speed / 3600.0;
            if (total_hours / 24.0 > config.max_transit_days) total_hours = config.max_transit_days * 24.0;
            global_segment += 1;
        }
    }
    var weather_digest: [32]u8 = undefined;
    weather_hasher.final(&weather_digest);
    return .{
        .lost = false,
        .days = total_hours / 24.0,
        .cargo_t = model.design.cargo_capacity_t,
        .crew_lost = 0,
        .weather_trace_sha256 = std.fmt.bytesToHex(weather_digest, .lower),
    };
}

fn fleetRequiredFreightRate(models: []const ClassModel, accumulators: []const ClassAccumulator, config: BackendConfig) f64 {
    var total_cost: f64 = 0;
    var total_delivered: f64 = 0;
    for (models, accumulators) |model, accumulator| {
        const trials = accumulator.survived + accumulator.losses;
        if (trials == 0) continue;
        const loss_rate = @as(f64, @floatFromInt(accumulator.losses)) / @as(f64, @floatFromInt(trials));
        const voyage_days = if (accumulator.survived > 0)
            accumulator.days_survived_sum / @as(f64, @floatFromInt(accumulator.survived))
        else
            config.max_transit_days;
        const annual = econ.model.annual(
            .{ .hull_cu = model.design.unit_cost_units * 0.82, .propulsion_cu = model.design.unit_cost_units * 0.18 },
            .{ .interest_rate = config.economics.interest_rate, .life_years = config.economics.life_years },
            .{
                .crew_cu_per_year = @as(f64, @floatFromInt(model.design.crew)) * config.economics.crew_cost_units_per_person_year,
                .maintenance_frac = config.economics.maintenance_fraction,
                .insurance_frac = config.economics.insurance_fraction,
            },
            .{ .energy_kwh = 0, .energy_price_cu_per_kwh = 0, .port_cu = config.economics.port_cost_units_per_voyage },
            .{
                .voyage_days = voyage_days,
                .turnaround_days = config.economics.turnaround_days,
                .loss_rate = loss_rate,
                .cargo_t = model.design.cargo_capacity_t,
                .freight_rate_cu_per_t = 0,
                .operating_days_per_year = config.economics.operating_days_per_year,
            },
        );
        const count: f64 = @floatFromInt(model.design.count);
        total_cost += annual.total_cost_cu * count;
        total_delivered += annual.cargo_delivered_t * count;
    }
    return if (total_delivered > 0) total_cost / total_delivered else std.math.inf(f64);
}

fn containsSeed(seeds: []const u64, seed: u64) bool {
    for (seeds) |candidate| if (candidate == seed) return true;
    return false;
}

fn fraction(value: f64) bool {
    return std.math.isFinite(value) and value >= 0 and value <= 1;
}

test "Mercury fleet backend emits a verifiable deterministic replay" {
    // Edges must span [0, ...] / [0, 180] per historical_env.validate; the
    // single observation sits in the 8-9 m/s x 90-120 deg bin (index 4).
    const counts = [_]u32{ 0, 0, 0, 0, 1, 0 };
    const months = [_]historical_env.MonthlyHistogram{
        .{ .month = 1, .observation_count = 1, .joint_counts = &counts },  .{ .month = 2, .observation_count = 1, .joint_counts = &counts },
        .{ .month = 3, .observation_count = 1, .joint_counts = &counts },  .{ .month = 4, .observation_count = 1, .joint_counts = &counts },
        .{ .month = 5, .observation_count = 1, .joint_counts = &counts },  .{ .month = 6, .observation_count = 1, .joint_counts = &counts },
        .{ .month = 7, .observation_count = 1, .joint_counts = &counts },  .{ .month = 8, .observation_count = 1, .joint_counts = &counts },
        .{ .month = 9, .observation_count = 1, .joint_counts = &counts },  .{ .month = 10, .observation_count = 1, .joint_counts = &counts },
        .{ .month = 11, .observation_count = 1, .joint_counts = &counts }, .{ .month = 12, .observation_count = 1, .joint_counts = &counts },
    };
    const nodes = [_]historical_env.RouteNode{ .{ .name = "A", .lat_deg = 0, .lon_deg = 0 }, .{ .name = "B", .lat_deg = 0, .lon_deg = 1 } };
    const environment: historical_env.Environment = .{
        .schema_version = historical_env.schema_id,
        .dataset_id = "fixture",
        .source = .{ .title = "x", .citation = "x", .doi = "x", .download_url = "x", .license = "CC-BY-3.0", .archive_sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .archive_member = "x", .records_in_archive = 1 },
        .selection = .{ .year_min = 1750, .year_max = 1805, .route_corridor_nm = 10, .selected_observations = 1, .method = "fixture" },
        .uncertainty = .{ .model_id = "fixture", .represented = &.{}, .not_represented = &.{}, .sampling = "fixture" },
        .wind_speed_edges_mps = &.{ 0, 8, 9 },
        .relative_wind_angle_edges_deg = &.{ 0, 90, 120, 180 },
        .legs = &.{.{ .leg_id = "leg", .course_bearing_deg = 90, .route_nodes = &nodes, .monthly = &months }},
    };
    const seeds = [_]u64{17781001};
    const mission: arena.types.Mission = .{
        .schema_version = arena.types.mission_schema,
        .mission_id = "mercury-1778-outbound",
        .mission_version = "v0",
        .ruleset_id = "rules",
        .title = "x",
        .summary = "x",
        .currency_unit = "u",
        .era = .{ .label = "x", .start_year = 1778, .end_year = 1779, .mode = .era_constrained_counterfactual },
        .route = .{ .origin = "A", .destination = "B", .waypoints = &.{}, .nominal_distance_nm = 60 },
        .rng = .{ .algorithm = arena.counter_rng.algorithm_id, .streams = &.{ .weather, .damage }, .public_seeds = &seeds, .hidden_seed_commitment_sha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" },
        .fleet_requirements = .{ .min_vessels = 1, .max_vessels = 4, .min_nominal_cargo_t = 1, .min_delivered_cargo_t = 1, .max_budget_units = 1000, .max_loss_fraction = 1, .max_crew_casualty_fraction = 1 },
        .design_bounds = .{ .min_length_m = 1, .max_length_m = 80, .min_beam_m = 1, .max_beam_m = 20, .min_draft_m = 1, .max_draft_m = 10, .min_displacement_t = 1, .max_displacement_t = 5000, .min_block_coefficient = 0.1, .max_block_coefficient = 0.9, .min_length_beam_ratio = 1, .max_length_beam_ratio = 10, .min_beam_draft_ratio = 1, .max_beam_draft_ratio = 10, .min_crew_per_vessel = 1, .max_crew_per_vessel = 200, .max_displacement_error_fraction = 0.1 },
        .evaluation = .{ .min_scenarios = 2, .max_delivered_to_nominal_ratio = 1, .ranking = "epsilon_pareto_v1" },
        .allowed_materials = &.{.oak},
        .allowed_propulsion = &.{.sail},
        .allowed_hull_forms = &.{.monohull},
        .objectives = &.{.{ .name = .delivered_cargo_t, .direction = .maximize, .aggregate = .mean, .epsilon = 0.1 }},
        .sources = &.{.{ .source_id = "x", .title = "x", .url = "x", .license = "x", .note = "x" }},
    };
    const fleet = [_]arena.types.VesselDesign{.{
        .design_id = "merchant",
        .class_name = "Merchant",
        .count = 1,
        .hull_form = .monohull,
        .material = .oak,
        .propulsion = .sail,
        .length_m = 38,
        .beam_m = 10.5,
        .draft_m = 4.5,
        .block_coefficient = 0.62,
        .displacement_t = 1141.04,
        .cargo_capacity_t = 180,
        .sail_area_m2 = 500,
        .crew = 70,
        .unit_cost_units = 300,
    }};
    const submission: arena.types.Submission = .{ .schema_version = arena.types.submission_schema, .submission_id = "entry", .mission_id = mission.mission_id, .mission_version = "v0", .ruleset_id = "rules", .track = .human_ai, .entrant = "x", .provenance = .{ .yard_revision = "x", .zig_version = "0.16.0", .authoring_system = "x" }, .fleet = &fleet };
    const config: BackendConfig = .{
        .schema_version = schema_id,
        .backend_version = backend_version,
        .scenario_count = 2,
        .start_month = 1,
        .segment_nm = 30,
        .becalmed_floor_mps = 0.2,
        .storm_threshold_mps = 20,
        .storm_loss_probability = 0,
        .storm_severity_exponent = 2,
        .max_segment_loss_probability = 0.1,
        .max_transit_days = 400,
        .min_gm_m = 0.3,
        .gate_wind_mps = 8,
        .max_heel_deg = 40,
        .require_is_code = true,
        .economics = .{ .interest_rate = 0.05, .life_years = 20, .crew_cost_units_per_person_year = 1, .maintenance_fraction = 0.03, .insurance_fraction = 0.01, .port_cost_units_per_voyage = 1, .turnaround_days = 30, .operating_days_per_year = 350 },
    };
    var memory = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer memory.deinit();
    const run = try evaluate(memory.allocator(), mission, submission, environment, config, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", 17781001);
    const views = try memory.allocator().alloc(arena.replay.Event, run.replay_events.len);
    for (views, run.replay_events) |*view, *event| view.* = event.view();
    try std.testing.expect(arena.replay.verify(views));
    try std.testing.expect(run.simulation.metrics.delivered_cargo_t > 0);
    try std.testing.expectEqual(run.replay_events.len, run.simulation.replay_event_count);
}
