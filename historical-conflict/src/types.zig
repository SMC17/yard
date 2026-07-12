//! Versioned public types for the governed 1778 aggregate conflict model.

pub const schema_id = "yard.historical-conflict.scenario.v0";
pub const backend_id = "yard.historical-conflict.aggregate-1778.v0";

pub const Side = enum { convoy, opposing };

pub const VesselRole = enum {
    merchantman,
    convoy_escort,
    period_cruiser,
    dispatch_sloop,
};

/// The enum deliberately includes later capabilities so the policy validator
/// can reject anachronistic submissions with a stable violation code.
pub const Capability = enum {
    wooden_primary_structure,
    canvas_sail,
    sail_propulsion,
    human_lookout,
    signal_flags,
    lantern_signals,
    speaking_trumpet,
    manual_pump,
    smoothbore_muzzle_loading_cannon,
    black_powder,
    solid_round_shot,
    iron_fasteners,

    steam_propulsion,
    iron_primary_structure,
    steel_primary_structure,
    rifled_breech_loading_cannon,
    smokeless_powder,
    radio,
    radar,
    sonar,
    electronic_fire_control,
    guided_weapon,
    satellite_navigation,
    turbine,
    diesel,
};

pub const SignalKind = enum {
    signal_flags,
    lantern_signals,
    speaking_trumpet,
    radio,
    data_link,
};

pub const SourceKind = enum {
    primary_log,
    museum_catalogue,
    public_reference,
    model_assumption,
};

pub const Source = struct {
    source_id: []const u8,
    kind: SourceKind,
    title: []const u8,
    uri: []const u8,
    license: []const u8,
    note: []const u8,
};

/// A screening-model parameter with an explicit uncertainty interval and a
/// source or assumption record. Sampling is uniform on [minimum, maximum].
pub const UncertainF64 = struct {
    central: f64,
    minimum: f64,
    maximum: f64,
    source_id: []const u8,
};

pub const Environment = struct {
    wind_speed_mps: UncertainF64,
    sea_severity: UncertainF64,
    visibility_fraction: UncertainF64,
};

pub const Command = struct {
    signal: SignalKind,
    order_delay_seconds: UncertainF64,
    signal_failure_probability: UncertainF64,
};

pub const Crew = struct {
    complement: u16,
    initial_morale: UncertainF64,
    training_fraction: UncertainF64,
    surrender_morale_threshold: f64,
};

pub const Gunnery = struct {
    gun_count: u16,
    shot_rounds: u32,
    powder_kg: f64,
    shot_mass_kg: f64,
    powder_per_round_kg: UncertainF64,
    reload_seconds: UncertainF64,
    effective_range_m: UncertainF64,
    hit_probability_at_reference: UncertainF64,
    damage_points_per_hit: UncertainF64,
    crew_loss_probability_per_hit: UncertainF64,
    fire_probability_per_hit: UncertainF64,
    flooding_probability_per_hit: UncertainF64,
};

pub const DamageControl = struct {
    hull_integrity_points: f64,
    flooding_capacity: f64,
    fire_suppression_per_step: UncertainF64,
    pumping_per_step: UncertainF64,
    withdrawal_hull_fraction: f64,
};

pub const Vessel = struct {
    vessel_id: []const u8,
    side: Side,
    role: VesselRole,
    displacement_t: f64,
    capabilities: []const Capability,
    provenance_ids: []const []const u8,
    command: Command,
    crew: Crew,
    gunnery: Gunnery,
    damage_control: DamageControl,
};

pub const Scenario = struct {
    schema_version: []const u8,
    scenario_id: []const u8,
    title: []const u8,
    year: i32,
    seed: u64,
    timestep_seconds: u32,
    max_steps: u32,
    initial_range_m: UncertainF64,
    environment: Environment,
    sources: []const Source,
    vessels: []const Vessel,
};

pub const VesselStatus = enum {
    active,
    disengaged,
    surrendered,
    sunk,
};

pub const VesselOutcome = struct {
    vessel_id: []const u8,
    side: Side,
    status: VesselStatus,
    initial_crew: u32,
    crew_remaining: u32,
    crew_lost: u32,
    initial_rounds: u32,
    rounds_fired: u32,
    rounds_remaining: u32,
    initial_powder_kg: f64,
    powder_used_kg: f64,
    powder_remaining_kg: f64,
    hull_integrity_fraction: f64,
    fire_level: f64,
    flooding_level: f64,
    morale: f64,
};

pub const Conservation = struct {
    crew: bool,
    ammunition: bool,
    powder: bool,
};

pub const Summary = struct {
    schema_version: []const u8 = "yard.historical-conflict.result.v0",
    backend: []const u8 = backend_id,
    scenario_sha256: [64]u8,
    scenario_id: []const u8,
    year: i32,
    seed: u64,
    steps_completed: u32,
    initial_crew: u64,
    crew_remaining: u64,
    crew_lost: u64,
    initial_rounds: u64,
    rounds_fired: u64,
    rounds_remaining: u64,
    initial_powder_kg: f64,
    powder_used_kg: f64,
    powder_remaining_kg: f64,
    surrendered: u32,
    disengaged: u32,
    sunk: u32,
    conservation: Conservation,
    replay_algorithm: []const u8,
    replay_event_count: u64,
    replay_head_sha256: [64]u8,
};
