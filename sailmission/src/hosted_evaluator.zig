//! Trusted hosted adapter for the Mercury fleet evaluator.
//!
//! The hidden-season artifact embeds exact, content-addressed environment and
//! backend JSON bytes. This keeps the evaluator hermetic inside the isolated
//! VM: no network or undeclared companion file is needed at evaluation time.

const std = @import("std");
const arena = @import("yard_arena");
const historical_env = @import("historical_env.zig");
const mercury = @import("mercury.zig");

pub const hidden_season_schema = "yard.hosted.mercury-hidden-season.v1";
pub const evaluator_version = "yard-mercury-hosted-v1";
pub const runner_protocol = "yard-hosted-evaluator-v1";

const max_safe_json_integer: u64 = 9_007_199_254_740_991;
const max_environment_bytes: usize = 4 * 1024 * 1024;
const max_backend_config_bytes: usize = 256 * 1024;

pub const Aggregation = enum {
    single_seed,
};

pub const Encoding = enum {
    base64_rfc4648,
};

pub const EmbeddedJson = struct {
    encoding: Encoding,
    media_type: []const u8,
    content_sha256: []const u8,
    content_base64: []const u8,
};

pub const HiddenSeason = struct {
    schema_version: []const u8,
    evaluator_version: []const u8,
    runner_protocol: []const u8,
    aggregation: Aggregation,
    mission_sha256: []const u8,
    seed: u64,
    environment: EmbeddedJson,
    backend_config: EmbeddedJson,
};

pub const DecodedHiddenSeason = struct {
    parsed: std.json.Parsed(HiddenSeason),
    environment_json: []u8,
    backend_config_json: []u8,

    pub fn deinit(self: *DecodedHiddenSeason, allocator: std.mem.Allocator) void {
        allocator.free(self.environment_json);
        allocator.free(self.backend_config_json);
        self.parsed.deinit();
        self.* = undefined;
    }
};

pub const Artifacts = struct {
    result_json: []u8,
    scorecard_json: []u8,
    replay_jsonl: []u8,
};

pub const Error = error{
    InvalidHiddenSeason,
    InvalidMission,
    InvalidSubmission,
    MissionDigestMismatch,
    EmbeddedArtifactDigestMismatch,
    UnsupportedAggregation,
    SeedNotPublished,
    ArtifactTooLarge,
    OutOfMemory,
};

/// Construct the exact hidden artifact accepted by `evaluateHosted`.
///
/// Version 1 deliberately evaluates one published seed. It does not aggregate
/// several independent seeds; a later schema must specify that statistic and
/// bind every seed before it may claim multi-seed season results.
pub fn packHiddenSeason(
    allocator: std.mem.Allocator,
    mission_json: []const u8,
    environment_json: []const u8,
    backend_config_json: []const u8,
    seed: u64,
) ![]u8 {
    if (environment_json.len > max_environment_bytes or backend_config_json.len > max_backend_config_bytes)
        return Error.ArtifactTooLarge;

    var mission = std.json.parseFromSlice(arena.types.Mission, allocator, mission_json, .{}) catch
        return Error.InvalidMission;
    defer mission.deinit();
    if (!containsSeed(mission.value.rng.public_seeds, seed) or seed > max_safe_json_integer)
        return Error.SeedNotPublished;

    const environment = historical_env.parse(allocator, environment_json) catch return Error.InvalidHiddenSeason;
    defer environment.deinit();
    const config = mercury.parseConfig(allocator, backend_config_json) catch return Error.InvalidHiddenSeason;
    defer config.deinit();

    const mission_sha256 = sha256Hex(mission_json);
    const environment_sha256 = sha256Hex(environment_json);
    const backend_config_sha256 = sha256Hex(backend_config_json);
    const environment_base64 = try encodeBase64(allocator, environment_json);
    defer allocator.free(environment_base64);
    const backend_config_base64 = try encodeBase64(allocator, backend_config_json);
    defer allocator.free(backend_config_base64);

    const hidden: HiddenSeason = .{
        .schema_version = hidden_season_schema,
        .evaluator_version = evaluator_version,
        .runner_protocol = runner_protocol,
        .aggregation = .single_seed,
        .mission_sha256 = &mission_sha256,
        .seed = seed,
        .environment = .{
            .encoding = .base64_rfc4648,
            .media_type = "application/json",
            .content_sha256 = &environment_sha256,
            .content_base64 = environment_base64,
        },
        .backend_config = .{
            .encoding = .base64_rfc4648,
            .media_type = "application/json",
            .content_sha256 = &backend_config_sha256,
            .content_base64 = backend_config_base64,
        },
    };
    return stringifyAlloc(allocator, hidden);
}

pub fn decodeHiddenSeason(allocator: std.mem.Allocator, hidden_json: []const u8) !DecodedHiddenSeason {
    var parsed = std.json.parseFromSlice(HiddenSeason, allocator, hidden_json, .{}) catch
        return Error.InvalidHiddenSeason;
    errdefer parsed.deinit();
    const hidden = parsed.value;
    if (!std.mem.eql(u8, hidden.schema_version, hidden_season_schema) or
        !std.mem.eql(u8, hidden.evaluator_version, evaluator_version) or
        !std.mem.eql(u8, hidden.runner_protocol, runner_protocol) or
        hidden.aggregation != .single_seed or
        hidden.seed > max_safe_json_integer or
        !validSha256Hex(hidden.mission_sha256))
    {
        return Error.InvalidHiddenSeason;
    }

    const environment_json = try decodeEmbeddedJson(allocator, hidden.environment, max_environment_bytes);
    errdefer allocator.free(environment_json);
    const backend_config_json = try decodeEmbeddedJson(allocator, hidden.backend_config, max_backend_config_bytes);
    errdefer allocator.free(backend_config_json);

    return .{
        .parsed = parsed,
        .environment_json = environment_json,
        .backend_config_json = backend_config_json,
    };
}

/// Run the real Mercury physics/economics backend and Arena feasibility scorer.
/// No reference result or trusted fixture participates in this path.
pub fn evaluateHosted(
    allocator: std.mem.Allocator,
    mission_json: []const u8,
    hidden_json: []const u8,
    submission_json: []const u8,
) !Artifacts {
    var mission = std.json.parseFromSlice(arena.types.Mission, allocator, mission_json, .{}) catch
        return Error.InvalidMission;
    defer mission.deinit();
    var submission = std.json.parseFromSlice(arena.types.Submission, allocator, submission_json, .{}) catch
        return Error.InvalidSubmission;
    defer submission.deinit();
    var hidden = try decodeHiddenSeason(allocator, hidden_json);
    defer hidden.deinit(allocator);

    const mission_sha256 = sha256Hex(mission_json);
    const submission_sha256 = sha256Hex(submission_json);
    const season_commitment_sha256 = sha256Hex(hidden_json);
    if (!std.mem.eql(u8, hidden.parsed.value.mission_sha256, &mission_sha256))
        return Error.MissionDigestMismatch;
    if (!containsSeed(mission.value.rng.public_seeds, hidden.parsed.value.seed))
        return Error.SeedNotPublished;

    const environment = historical_env.parse(allocator, hidden.environment_json) catch
        return Error.InvalidHiddenSeason;
    defer environment.deinit();
    const config = mercury.parseConfig(allocator, hidden.backend_config_json) catch
        return Error.InvalidHiddenSeason;
    defer config.deinit();
    const environment_sha256 = compositeEnvironmentSha(hidden.environment_json, hidden.backend_config_json);

    // In hosted operation the signed season manifest commits the hidden
    // artifact. Replace the public mission's legacy seed-commitment placeholder
    // in memory so the generic Arena scorer validates the stronger hosted
    // commitment without changing the exact public mission bytes or its hash.
    mission.value.rng.hidden_seed_commitment_sha256 = &season_commitment_sha256;
    const mercury_run = try mercury.evaluate(
        allocator,
        mission.value,
        submission.value,
        environment.value,
        config.value,
        &mission_sha256,
        &submission_sha256,
        &environment_sha256,
        hidden.parsed.value.seed,
    );

    const hosted_replay = try bindReplay(
        allocator,
        mercury_run.replay_events,
        &mission_sha256,
        &submission_sha256,
        &environment_sha256,
        &season_commitment_sha256,
    );
    const replay_head = replayHead(hosted_replay);
    var simulation = mercury_run.simulation;
    simulation.replay_head_sha256 = &replay_head;
    simulation.replay_event_count = hosted_replay.len;
    simulation.season_commitment_sha256 = &season_commitment_sha256;

    const result_json = try stringifyAlloc(allocator, simulation);
    errdefer allocator.free(result_json);
    const simulation_result_sha256 = sha256Hex(result_json);
    const run_id = runIdHex(
        &mission_sha256,
        &submission_sha256,
        &simulation_result_sha256,
        &season_commitment_sha256,
    );
    var scorecard = try arena.evaluator.evaluate(
        allocator,
        mission.value,
        submission.value,
        simulation,
        .{
            .run_id = &run_id,
            .mission_sha256 = &mission_sha256,
            .submission_sha256 = &submission_sha256,
            .simulation_result_sha256 = &simulation_result_sha256,
        },
    );
    defer arena.evaluator.deinitScorecard(allocator, &scorecard);
    scorecard.evaluator_version = evaluator_version;
    const scorecard_json = try stringifyAlloc(allocator, scorecard);
    errdefer allocator.free(scorecard_json);
    const replay_jsonl = try stringifyReplay(allocator, hosted_replay);
    errdefer allocator.free(replay_jsonl);

    return .{
        .result_json = result_json,
        .scorecard_json = scorecard_json,
        .replay_jsonl = replay_jsonl,
    };
}

fn decodeEmbeddedJson(allocator: std.mem.Allocator, artifact: EmbeddedJson, max_bytes: usize) ![]u8 {
    if (artifact.encoding != .base64_rfc4648 or
        !std.mem.eql(u8, artifact.media_type, "application/json") or
        !validSha256Hex(artifact.content_sha256))
    {
        return Error.InvalidHiddenSeason;
    }
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(artifact.content_base64) catch
        return Error.InvalidHiddenSeason;
    if (decoded_len == 0 or decoded_len > max_bytes) return Error.ArtifactTooLarge;
    const decoded = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(decoded);
    std.base64.standard.Decoder.decode(decoded, artifact.content_base64) catch
        return Error.InvalidHiddenSeason;

    // Reject alternative encodings so exact hidden bytes have one portable
    // representation across the Zig evaluator and TypeScript control plane.
    const canonical = try encodeBase64(allocator, decoded);
    defer allocator.free(canonical);
    if (!std.mem.eql(u8, canonical, artifact.content_base64)) return Error.InvalidHiddenSeason;
    const digest = sha256Hex(decoded);
    if (!std.mem.eql(u8, &digest, artifact.content_sha256))
        return Error.EmbeddedArtifactDigestMismatch;
    return decoded;
}

fn bindReplay(
    allocator: std.mem.Allocator,
    source: []const arena.replay.OwnedEvent,
    mission_sha256: []const u8,
    submission_sha256: []const u8,
    environment_sha256: []const u8,
    season_commitment_sha256: []const u8,
) ![]arena.replay.OwnedEvent {
    var chain: arena.replay.Chain = .{};
    var rebound: std.ArrayList(arena.replay.OwnedEvent) = .empty;
    errdefer rebound.deinit(allocator);
    const payload = try std.fmt.allocPrint(
        allocator,
        "mission_sha256={s};submission_sha256={s};environment_sha256={s};season_commitment_sha256={s};backend_version={s};evaluator_version={s}",
        .{ mission_sha256, submission_sha256, environment_sha256, season_commitment_sha256, mercury.backend_version, evaluator_version },
    );
    try rebound.append(allocator, chain.append("hosted_inputs_bound", payload));
    for (source) |event| try rebound.append(allocator, chain.append(event.kind, event.payload));
    return rebound.toOwnedSlice(allocator);
}

fn replayHead(events: []const arena.replay.OwnedEvent) [64]u8 {
    if (events.len == 0) return arena.replay.zero_hash_hex.*;
    return events[events.len - 1].event_sha256;
}

fn stringifyReplay(allocator: std.mem.Allocator, events: []const arena.replay.OwnedEvent) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    errdefer output.deinit();
    for (events) |*event| {
        try std.json.Stringify.value(event.view(), .{}, &output.writer);
        try output.writer.writeByte('\n');
    }
    return output.toOwnedSlice();
}

fn stringifyAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    errdefer output.deinit();
    try std.json.Stringify.value(value, .{ .whitespace = .indent_2 }, &output.writer);
    try output.writer.writeByte('\n');
    return output.toOwnedSlice();
}

fn encodeBase64(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const encoded = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
    return @constCast(std.base64.standard.Encoder.encode(encoded, bytes));
}

pub fn sha256Hex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

fn compositeEnvironmentSha(environment: []const u8, config: []const u8) [64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("yard-mercury/environment/v0\x00");
    hasher.update(environment);
    hasher.update("\x00");
    hasher.update(config);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

fn runIdHex(
    mission_sha256: []const u8,
    submission_sha256: []const u8,
    simulation_result_sha256: []const u8,
    season_commitment_sha256: []const u8,
) [64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("yard-hosted-evaluator/run/v1\x00");
    hasher.update(mission_sha256);
    hasher.update("\x00");
    hasher.update(submission_sha256);
    hasher.update("\x00");
    hasher.update(simulation_result_sha256);
    hasher.update("\x00");
    hasher.update(season_commitment_sha256);
    hasher.update("\x00");
    hasher.update(evaluator_version);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

fn containsSeed(seeds: []const u64, seed: u64) bool {
    for (seeds) |candidate| if (candidate == seed) return true;
    return false;
}

fn validSha256Hex(value: []const u8) bool {
    if (value.len != 64) return false;
    for (value) |byte| if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) return false;
    return true;
}

test "hidden season rejects embedded content tampering" {
    const mission_json = @embedFile("mercury_mission_json");
    const environment_json = @embedFile("mercury_environment_json");
    const config_json = @embedFile("mercury_backend_config_json");
    const hidden_json = try packHiddenSeason(std.testing.allocator, mission_json, environment_json, config_json, 17781001);
    defer std.testing.allocator.free(hidden_json);

    var tampered = try std.testing.allocator.dupe(u8, hidden_json);
    defer std.testing.allocator.free(tampered);
    const marker = "\"content_base64\": \"";
    const start = (std.mem.indexOf(u8, tampered, marker) orelse return error.TestUnexpectedResult) + marker.len;
    tampered[start] = if (tampered[start] == 'A') 'B' else 'A';
    try std.testing.expectError(Error.EmbeddedArtifactDigestMismatch, decodeHiddenSeason(std.testing.allocator, tampered));
}

test "hosted evaluator is deterministic and binds every artifact" {
    const mission_json = @embedFile("mercury_mission_json");
    const environment_json = @embedFile("mercury_environment_json");
    const config_json = @embedFile("mercury_backend_config_json");
    const submission_json = @embedFile("mercury_submission_example_json");

    var memory = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer memory.deinit();
    const allocator = memory.allocator();
    const hidden_json = try packHiddenSeason(allocator, mission_json, environment_json, config_json, 17781001);
    const first = try evaluateHosted(allocator, mission_json, hidden_json, submission_json);
    const second = try evaluateHosted(allocator, mission_json, hidden_json, submission_json);
    try std.testing.expectEqualStrings(first.result_json, second.result_json);
    try std.testing.expectEqualStrings(first.scorecard_json, second.scorecard_json);
    try std.testing.expectEqualStrings(first.replay_jsonl, second.replay_jsonl);

    var result = try std.json.parseFromSlice(arena.types.SimulationResult, allocator, first.result_json, .{});
    defer result.deinit();
    var scorecard = try std.json.parseFromSlice(arena.types.Scorecard, allocator, first.scorecard_json, .{});
    defer scorecard.deinit();
    const mission_sha256 = sha256Hex(mission_json);
    const submission_sha256 = sha256Hex(submission_json);
    const season_sha256 = sha256Hex(hidden_json);
    const result_sha256 = sha256Hex(first.result_json);
    try std.testing.expectEqualStrings(&mission_sha256, scorecard.value.mission_sha256);
    try std.testing.expectEqualStrings(&submission_sha256, scorecard.value.submission_sha256);
    try std.testing.expectEqualStrings(&season_sha256, scorecard.value.season_commitment_sha256);
    try std.testing.expectEqualStrings(&result_sha256, scorecard.value.simulation_result_sha256);
    try std.testing.expectEqualStrings(evaluator_version, scorecard.value.evaluator_version);
    try std.testing.expectEqualStrings(result.value.environment_sha256, scorecard.value.environment_sha256);
    try std.testing.expectEqual(result.value.replay_event_count, scorecard.value.replay_event_count);

    var mission_with_whitespace = try allocator.alloc(u8, mission_json.len + 1);
    @memcpy(mission_with_whitespace[0..mission_json.len], mission_json);
    mission_with_whitespace[mission_json.len] = '\n';
    try std.testing.expectError(
        Error.MissionDigestMismatch,
        evaluateHosted(allocator, mission_with_whitespace, hidden_json, submission_json),
    );
}
