//! Mission spec + submission schema (yard-mission/v0).
//!
//! A mission is a constraint envelope + environment + objective set.
//! A submission is a parametric vessel + loading + propulsion.
//! Both are plain JSON documents so agents, humans, and CI submit the
//! same artifact.

const std = @import("std");

pub const Error = error{
    BadSchema,
    OutOfMemory,
    ParseFailed,
};

pub const Direction = enum { min, max };

pub const Objective = struct {
    id: []const u8,
    direction: Direction,
};

pub const Waypoint = struct {
    name: []const u8,
    lat_deg: f64,
    lon_deg: f64,
};

pub const Era = struct {
    id: []const u8,
    max_loa_m: f64,
    max_beam_m: f64,
    max_draft_m: f64,
    /// Minimum freeboard as a fraction of hull depth (load-line proxy).
    min_freeboard_frac: f64,
    /// Maximum L/D ratio — hull-girder strength proxy until the CSR gate lands.
    max_l_over_d: f64,
};

pub const Environment = struct {
    /// Weibull shape parameter for per-leg significant wave height draws.
    hs_weibull_k: f64,
    /// Weibull scale parameter [m].
    hs_weibull_lambda_m: f64,
    /// Hs above this counts as a storm encounter [m].
    storm_hs_m: f64,
    /// Probability of vessel loss per storm encounter.
    storm_loss_prob: f64,
};

pub const MonteCarlo = struct {
    runs: u32,
    base_seed: u64,
    /// Missing in early v0 fixtures; those retain the old std.Random sequence.
    rng_algorithm: []const u8 = "zig-default-prng-v0",
};

pub const Gates = struct {
    /// Minimum free-surface-corrected GM [m].
    min_gm_m: f64,
    /// Require IMO IS Code 2008 Part A 2.2 overall pass.
    require_is_code: bool,
    /// Minimum attainable calm-water speed [m/s]; propulsion feasibility.
    min_calm_speed_mps: f64,
};

pub const MissionSpec = struct {
    schema: []const u8,
    id: []const u8,
    title: []const u8 = "",
    era: Era,
    waypoints: []const Waypoint,
    environment: Environment,
    monte_carlo: MonteCarlo,
    gates: Gates,
    objectives: []const Objective,
};

pub const Tank = struct {
    l_m: f64,
    b_m: f64,
    rho_fluid: f64,
};

pub const Hull = struct {
    loa_m: f64,
    beam_m: f64,
    draft_m: f64,
    depth_m: f64,
    cb: f64,
    cm: f64,
    cp: f64,
    cwp: f64,
    lcb_pct: f64,
    wetted_surface_m2: f64,
    displacement_m3: f64,
};

pub const Loading = struct {
    kg_m: f64,
    cargo_t: f64,
    tanks: []const Tank = &.{},
};

pub const Propulsion = struct {
    installed_kw: f64,
    propulsive_efficiency: f64,
    /// Fraction of installed power available in service.
    service_fraction: f64,
};

pub const Submission = struct {
    schema: []const u8,
    id: []const u8,
    author: []const u8 = "",
    hull: Hull,
    loading: Loading,
    propulsion: Propulsion,
};

pub const mission_schema_id = "yard-mission/v0";
pub const submission_schema_id = "yard-submission/v0";

pub fn parseMission(allocator: std.mem.Allocator, json: []const u8) Error!std.json.Parsed(MissionSpec) {
    const parsed = std.json.parseFromSlice(MissionSpec, allocator, json, .{}) catch |err| switch (err) {
        error.OutOfMemory => return Error.OutOfMemory,
        else => return Error.ParseFailed,
    };
    if (!std.mem.eql(u8, parsed.value.schema, mission_schema_id)) {
        parsed.deinit();
        return Error.BadSchema;
    }
    return parsed;
}

pub fn parseSubmission(allocator: std.mem.Allocator, json: []const u8) Error!std.json.Parsed(Submission) {
    const parsed = std.json.parseFromSlice(Submission, allocator, json, .{}) catch |err| switch (err) {
        error.OutOfMemory => return Error.OutOfMemory,
        else => return Error.ParseFailed,
    };
    if (!std.mem.eql(u8, parsed.value.schema, submission_schema_id)) {
        parsed.deinit();
        return Error.BadSchema;
    }
    return parsed;
}

pub const test_mission_json =
    \\{
    \\  "schema": "yard-mission/v0",
    \\  "id": "m0-coastal-trader",
    \\  "title": "Coastal trader - Rotterdam / Immingham round trip",
    \\  "era": {
    \\    "id": "modern",
    \\    "max_loa_m": 140.0,
    \\    "max_beam_m": 22.0,
    \\    "max_draft_m": 7.5,
    \\    "min_freeboard_frac": 0.05,
    \\    "max_l_over_d": 15.0
    \\  },
    \\  "waypoints": [
    \\    { "name": "Rotterdam", "lat_deg": 51.95, "lon_deg": 4.14 },
    \\    { "name": "Immingham", "lat_deg": 53.63, "lon_deg": -0.19 },
    \\    { "name": "Rotterdam", "lat_deg": 51.95, "lon_deg": 4.14 }
    \\  ],
    \\  "environment": {
    \\    "hs_weibull_k": 1.6,
    \\    "hs_weibull_lambda_m": 1.8,
    \\    "storm_hs_m": 6.5,
    \\    "storm_loss_prob": 0.02
    \\  },
    \\  "monte_carlo": { "runs": 200, "base_seed": 20260710, "rng_algorithm": "blake3-counter-v1" },
    \\  "gates": {
    \\    "min_gm_m": 0.15,
    \\    "require_is_code": true,
    \\    "min_calm_speed_mps": 3.0
    \\  },
    \\  "objectives": [
    \\    { "id": "voyage_days", "direction": "min" },
    \\    { "id": "loss_rate", "direction": "min" },
    \\    { "id": "transport_cost_index", "direction": "min" },
    \\    { "id": "cargo_delivered_t", "direction": "max" }
    \\  ]
    \\}
;

pub const test_submission_json =
    \\{
    \\  "schema": "yard-submission/v0",
    \\  "id": "baseline-coaster",
    \\  "author": "yard",
    \\  "hull": {
    \\    "loa_m": 100.0,
    \\    "beam_m": 16.0,
    \\    "draft_m": 6.0,
    \\    "depth_m": 9.0,
    \\    "cb": 0.65,
    \\    "cm": 0.98,
    \\    "cp": 0.66,
    \\    "cwp": 0.78,
    \\    "lcb_pct": -1.0,
    \\    "wetted_surface_m2": 2500.0,
    \\    "displacement_m3": 8500.0
    \\  },
    \\  "loading": {
    \\    "kg_m": 5.5,
    \\    "cargo_t": 5000.0,
    \\    "tanks": [
    \\      { "l_m": 20.0, "b_m": 8.0, "rho_fluid": 900.0 }
    \\    ]
    \\  },
    \\  "propulsion": {
    \\    "installed_kw": 4000.0,
    \\    "propulsive_efficiency": 0.65,
    \\    "service_fraction": 0.85
    \\  }
    \\}
;

test "parse mission spec" {
    const parsed = try parseMission(std.testing.allocator, test_mission_json);
    defer parsed.deinit();
    const m = parsed.value;
    try std.testing.expectEqualStrings("m0-coastal-trader", m.id);
    try std.testing.expectEqual(@as(usize, 3), m.waypoints.len);
    try std.testing.expectEqual(@as(usize, 4), m.objectives.len);
    try std.testing.expectEqual(Direction.max, m.objectives[3].direction);
    try std.testing.expectEqual(@as(u32, 200), m.monte_carlo.runs);
}

test "parse submission" {
    const parsed = try parseSubmission(std.testing.allocator, test_submission_json);
    defer parsed.deinit();
    const s = parsed.value;
    try std.testing.expectEqualStrings("baseline-coaster", s.id);
    try std.testing.expectEqual(@as(usize, 1), s.loading.tanks.len);
    try std.testing.expectApproxEqAbs(@as(f64, 16.0), s.hull.beam_m, 1e-12);
}

test "wrong schema rejected" {
    const bad =
        \\{ "schema": "yard-mission/v999", "id": "x", "era": {"id":"e","max_loa_m":1,"max_beam_m":1,"max_draft_m":1,"min_freeboard_frac":0,"max_l_over_d":1},
        \\  "waypoints": [], "environment": {"hs_weibull_k":1,"hs_weibull_lambda_m":1,"storm_hs_m":1,"storm_loss_prob":0},
        \\  "monte_carlo": {"runs":1,"base_seed":1}, "gates": {"min_gm_m":0,"require_is_code":false,"min_calm_speed_mps":0}, "objectives": [] }
    ;
    try std.testing.expectError(Error.BadSchema, parseMission(std.testing.allocator, bad));
}

test "unknown mission fields fail closed" {
    const bad =
        \\{ "schema": "yard-mission/v0", "id": "x", "typo_constraint": 1,
        \\  "era": {"id":"e","max_loa_m":1,"max_beam_m":1,"max_draft_m":1,"min_freeboard_frac":0,"max_l_over_d":1},
        \\  "waypoints": [], "environment": {"hs_weibull_k":1,"hs_weibull_lambda_m":1,"storm_hs_m":1,"storm_loss_prob":0},
        \\  "monte_carlo": {"runs":1,"base_seed":1}, "gates": {"min_gm_m":0,"require_is_code":false,"min_calm_speed_mps":0}, "objectives": [] }
    ;
    try std.testing.expectError(Error.ParseFailed, parseMission(std.testing.allocator, bad));
}

test "unknown submission fields fail closed" {
    const bad =
        \\{ "schema": "yard-submission/v0", "id": "x", "untrusted_score": 999,
        \\  "hull": {"loa_m":1,"beam_m":1,"draft_m":1,"depth_m":1,"cb":0.5,"cm":0.9,"cp":0.5,"cwp":0.7,"lcb_pct":0,"wetted_surface_m2":1,"displacement_m3":1},
        \\  "loading": {"kg_m":0.5,"cargo_t":1},
        \\  "propulsion": {"installed_kw":1,"propulsive_efficiency":0.5,"service_fraction":0.5} }
    ;
    try std.testing.expectError(Error.ParseFailed, parseSubmission(std.testing.allocator, bad));
}
