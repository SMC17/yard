//! Sail mission spec + submission schema (yard-sail-mission/v0).
//!
//! Age-of-Sail Trials rung: per-leg wind climates instead of a single wave
//! climate, rigs instead of engines, era envelopes from the era module.
//! Parsing fails closed (unknown fields are errors), matching the power
//! mission runner's anti-gaming posture.

const std = @import("std");

pub const Error = error{
    BadSchema,
    OutOfMemory,
    ParseFailed,
    LegCountMismatch,
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

/// Wind climate for one route leg.
pub const LegClimate = struct {
    /// Weibull shape for true wind speed draws.
    tws_weibull_k: f64,
    /// Weibull scale [m/s].
    tws_weibull_lambda_mps: f64,
    /// True wind angle off the course, drawn uniformly in this band [deg].
    twa_min_deg: f64,
    twa_max_deg: f64,
    /// True wind speed above this is a storm encounter [m/s].
    storm_tws_mps: f64,
    /// Probability of vessel loss per storm encounter.
    storm_loss_prob: f64,
};

pub const MonteCarlo = struct {
    runs: u32,
    base_seed: u64,
};

pub const Gates = struct {
    min_gm_m: f64,
    require_is_code: bool,
    /// Reference beam wind for the sail-carrying check [m/s].
    gate_wind_mps: f64 = 10.0,
    /// Maximum steady heel at the reference wind [deg].
    max_heel_deg: f64 = 15.0,
    /// Enforce the IMO weather criterion (IS Code 2.3) as a hard gate.
    /// Always computed and reported; missions opt in once their windage
    /// parameterization is validated.
    require_weather_criterion: bool = false,
};

pub const MissionSpec = struct {
    schema: []const u8,
    id: []const u8,
    title: []const u8 = "",
    /// Era envelope id resolved against the era module (e.g. "clipper").
    era_id: []const u8,
    waypoints: []const Waypoint,
    /// One climate per leg (waypoints.len - 1).
    legs: []const LegClimate,
    /// Weather is redrawn every segment of at most this length [nm].
    segment_nm: f64 = 500.0,
    /// Course-made-good floor when becalmed or unable to lay the course
    /// [m/s] (~10 nm/day of drift + working the ship).
    becalmed_floor_mps: f64 = 0.2,
    monte_carlo: MonteCarlo,
    gates: Gates,
    objectives: []const Objective,
};

pub const Hull = struct {
    loa_m: f64,
    beam_m: f64,
    draft_m: f64,
    depth_m: f64,
    /// Block coefficient (used for the era design record, not resistance).
    cb: f64,
    displacement_m3: f64,
    wetted_surface_m2: f64,
    kg_m: f64,
    /// Residuary resistance coefficient (documented v0 assumption; fine
    /// clipper hulls ~1.2e-3, full-bodied traders ~2.5e-3).
    cr: f64,
    /// Form factor on friction.
    form_factor: f64 = 1.2,
};

pub const RigKindTag = enum { square, fore_and_aft };

pub const Rig = struct {
    kind: RigKindTag,
    area_m2: f64,
    /// Square rig: closest brace to centreline [deg].
    min_brace_deg: f64 = 30.0,
    /// Fore-and-aft: effective rig height for induced drag [m].
    effective_height_m: f64 = 0.0,
};

pub const Submission = struct {
    schema: []const u8,
    id: []const u8,
    author: []const u8 = "",
    /// Structural material id resolved against the era module.
    material: []const u8,
    hull: Hull,
    rig: Rig,
};

pub const mission_schema_id = "yard-sail-mission/v0";
pub const submission_schema_id = "yard-sail-submission/v0";

pub fn parseMission(allocator: std.mem.Allocator, json: []const u8) Error!std.json.Parsed(MissionSpec) {
    const parsed = std.json.parseFromSlice(MissionSpec, allocator, json, .{}) catch |err| switch (err) {
        error.OutOfMemory => return Error.OutOfMemory,
        else => return Error.ParseFailed,
    };
    errdefer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.schema, mission_schema_id)) return Error.BadSchema;
    if (parsed.value.waypoints.len < 2 or parsed.value.legs.len != parsed.value.waypoints.len - 1)
        return Error.LegCountMismatch;
    return parsed;
}

pub fn parseSubmission(allocator: std.mem.Allocator, json: []const u8) Error!std.json.Parsed(Submission) {
    const parsed = std.json.parseFromSlice(Submission, allocator, json, .{}) catch |err| switch (err) {
        error.OutOfMemory => return Error.OutOfMemory,
        else => return Error.ParseFailed,
    };
    errdefer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.schema, submission_schema_id)) return Error.BadSchema;
    return parsed;
}

test "parse round trip and leg-count validation" {
    const fixtures = @import("fixtures.zig");
    const m = try parseMission(std.testing.allocator, fixtures.tea_race_mission_json);
    defer m.deinit();
    try std.testing.expectEqualStrings("m1-tea-race-1866", m.value.id);
    try std.testing.expectEqual(m.value.waypoints.len - 1, m.value.legs.len);

    const s = try parseSubmission(std.testing.allocator, fixtures.cutty_sark_json);
    defer s.deinit();
    try std.testing.expectEqual(RigKindTag.square, s.value.rig.kind);
    try std.testing.expect(s.value.rig.area_m2 > 2500);
}

test "unknown fields fail closed" {
    const bad =
        \\{ "schema": "yard-sail-mission/v0", "id": "x", "era_id": "clipper", "hax": 1,
        \\  "waypoints": [], "legs": [], "monte_carlo": {"runs":1,"base_seed":1},
        \\  "gates": {"min_gm_m":0,"require_is_code":false}, "objectives": [] }
    ;
    try std.testing.expectError(Error.ParseFailed, parseMission(std.testing.allocator, bad));
}
