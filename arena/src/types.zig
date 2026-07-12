//! Public wire types for Yard Arena missions, submissions, and scorecards.

pub const mission_schema = "yard.arena.mission.v0";
pub const submission_schema = "yard.arena.submission.v0";
pub const simulation_result_schema = "yard.arena.simulation-result.v0";
pub const scorecard_schema = "yard.arena.scorecard.v0";
pub const evaluator_version = "yard-arena-screening-v0.1.0";

pub const Track = enum {
    declared_human,
    human_ai,
    autonomous_agent,
    exhibition,
};

pub const Material = enum {
    oak,
    teak,
    softwood,
    iron,
    steel,
    aluminum,
    composite,
};

pub const Propulsion = enum {
    sail,
    sail_and_oar,
    steam,
    diesel,
    hybrid,
    electric,
    nuclear,
};

pub const HullForm = enum {
    monohull,
    catamaran,
    trimaran,
    submersible,
};

pub const RngStream = enum {
    weather,
    demand,
    damage,
    traffic,
    sensor_noise,
};

pub const Direction = enum {
    minimize,
    maximize,
};

pub const ObjectiveName = enum {
    delivered_cargo_t,
    mean_transit_days,
    p95_transit_days,
    total_cost_units,
    loss_fraction,
    crew_casualty_fraction,
    crew_exposure_days,
    emissions_t_co2e,
    required_freight_rate_units_per_t,
};

pub const Aggregate = enum {
    fixed,
    mean,
    median,
    p95,
    cvar90,
};

pub const ObjectiveSpec = struct {
    name: ObjectiveName,
    direction: Direction,
    aggregate: Aggregate,
    epsilon: f64,
};

pub const SourceRef = struct {
    source_id: []const u8,
    title: []const u8,
    url: []const u8,
    license: []const u8,
    note: []const u8,
};

pub const Era = struct {
    label: []const u8,
    start_year: u16,
    end_year: u16,
    mode: enum {
        historical_attested,
        era_constrained_counterfactual,
    },
};

pub const Route = struct {
    origin: []const u8,
    destination: []const u8,
    waypoints: []const []const u8,
    nominal_distance_nm: f64,
};

pub const RngPolicy = struct {
    algorithm: []const u8,
    streams: []const RngStream,
    public_seeds: []const u64,
    hidden_seed_commitment_sha256: []const u8,
};

pub const FleetRequirements = struct {
    min_vessels: u32,
    max_vessels: u32,
    min_nominal_cargo_t: f64,
    min_delivered_cargo_t: f64,
    max_budget_units: f64,
    max_mean_transit_days: ?f64 = null,
    max_loss_fraction: f64,
    max_crew_casualty_fraction: f64,
};

pub const DesignBounds = struct {
    min_length_m: f64,
    max_length_m: f64,
    min_beam_m: f64,
    max_beam_m: f64,
    min_draft_m: f64,
    max_draft_m: f64,
    min_displacement_t: f64,
    max_displacement_t: f64,
    min_block_coefficient: f64,
    max_block_coefficient: f64,
    min_length_beam_ratio: f64,
    max_length_beam_ratio: f64,
    min_beam_draft_ratio: f64,
    max_beam_draft_ratio: f64,
    min_crew_per_vessel: u32,
    max_crew_per_vessel: u32,
    max_displacement_error_fraction: f64,
};

pub const EvaluationPolicy = struct {
    min_scenarios: u32,
    max_delivered_to_nominal_ratio: f64,
    ranking: []const u8,
};

pub const Mission = struct {
    schema_version: []const u8,
    mission_id: []const u8,
    mission_version: []const u8,
    ruleset_id: []const u8,
    title: []const u8,
    summary: []const u8,
    currency_unit: []const u8,
    era: Era,
    route: Route,
    rng: RngPolicy,
    fleet_requirements: FleetRequirements,
    design_bounds: DesignBounds,
    allowed_materials: []const Material,
    allowed_propulsion: []const Propulsion,
    allowed_hull_forms: []const HullForm,
    objectives: []const ObjectiveSpec,
    evaluation: EvaluationPolicy,
    sources: []const SourceRef,
};

pub const Provenance = struct {
    yard_revision: []const u8,
    zig_version: []const u8,
    authoring_system: []const u8,
    ai_system: ?[]const u8 = null,
    method_uri: ?[]const u8 = null,
};

pub const VesselDesign = struct {
    design_id: []const u8,
    class_name: []const u8,
    count: u32,
    hull_form: HullForm,
    material: Material,
    propulsion: Propulsion,
    length_m: f64,
    beam_m: f64,
    draft_m: f64,
    block_coefficient: f64,
    displacement_t: f64,
    cargo_capacity_t: f64,
    sail_area_m2: f64,
    crew: u32,
    unit_cost_units: f64,
    /// Optional naval-architecture inputs. The official backend publishes
    /// its derivation policy when these are omitted.
    depth_m: ?f64 = null,
    kg_m: ?f64 = null,
    wetted_surface_m2: ?f64 = null,
    residuary_coefficient: ?f64 = null,
    form_factor: ?f64 = null,
    min_brace_deg: ?f64 = null,
};

pub const Submission = struct {
    schema_version: []const u8,
    submission_id: []const u8,
    mission_id: []const u8,
    mission_version: []const u8,
    ruleset_id: []const u8,
    track: Track,
    entrant: []const u8,
    provenance: Provenance,
    fleet: []const VesselDesign,
};

pub const SimulationMetrics = struct {
    delivered_cargo_t: f64,
    mean_transit_days: f64,
    p95_transit_days: f64,
    loss_fraction: f64,
    crew_casualty_fraction: f64,
    crew_exposure_days: ?f64 = null,
    emissions_t_co2e: ?f64 = null,
    required_freight_rate_units_per_t: ?f64 = null,
};

/// Produced by a trusted Yard simulation backend, never trusted from an entrant.
pub const SimulationResult = struct {
    schema_version: []const u8,
    evaluator_id: []const u8,
    mission_id: []const u8,
    mission_version: []const u8,
    submission_id: []const u8,
    mission_sha256: []const u8,
    submission_sha256: []const u8,
    backend_version: []const u8,
    environment_sha256: []const u8,
    replay_algorithm: []const u8,
    replay_head_sha256: []const u8,
    replay_event_count: u64,
    season_commitment_sha256: []const u8,
    seed: u64,
    scenario_count: u32,
    metrics: SimulationMetrics,
};

pub const ViolationCode = enum {
    empty_fleet,
    duplicate_design_id,
    fleet_count_below_minimum,
    fleet_count_above_maximum,
    invalid_numeric_value,
    dimension_out_of_bounds,
    ratio_out_of_bounds,
    displacement_mismatch,
    material_not_allowed,
    propulsion_not_allowed,
    hull_form_not_allowed,
    sail_area_required,
    crew_out_of_bounds,
    budget_exceeded,
    nominal_cargo_below_minimum,
    delivered_cargo_below_minimum,
    delivered_cargo_exceeds_envelope,
    transit_time_exceeded,
    loss_fraction_exceeded,
    crew_casualty_fraction_exceeded,
};

pub const Violation = struct {
    code: ViolationCode,
    subject: []const u8,
    detail: []const u8,
};

pub const ObjectiveValue = struct {
    name: ObjectiveName,
    direction: Direction,
    aggregate: Aggregate,
    epsilon: f64,
    value: f64,
};

pub const Scorecard = struct {
    schema_version: []const u8,
    evaluator_version: []const u8,
    evaluator_id: []const u8,
    run_id: []const u8,
    mission_id: []const u8,
    mission_version: []const u8,
    ruleset_id: []const u8,
    submission_id: []const u8,
    track: Track,
    mission_sha256: []const u8,
    submission_sha256: []const u8,
    simulation_result_sha256: []const u8,
    backend_version: []const u8,
    environment_sha256: []const u8,
    replay_algorithm: []const u8,
    replay_head_sha256: []const u8,
    replay_event_count: u64,
    season_commitment_sha256: []const u8,
    seed: u64,
    scenario_count: u32,
    feasible: bool,
    total_vessels: u32,
    total_cost_units: f64,
    total_nominal_cargo_t: f64,
    violations: []const Violation,
    objectives: []const ObjectiveValue,
};
