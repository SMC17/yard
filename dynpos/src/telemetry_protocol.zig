//! Versioned wire contract shared with the ArmadaClaw OTP telemetry backbone.

const std = @import("std");

pub const schema_id = "yard.telemetry.v1";
pub const state_kind = "vessel_state";
pub const command_kind = "thruster_command";
pub const max_payload_bytes: usize = 65_536;
pub const max_thrusters: usize = 8;

pub const Error = error{
    InvalidEnvelope,
    InvalidIdentifier,
    InvalidNumber,
    PayloadTooLarge,
    ParseFailed,
    OutOfMemory,
};

pub const VesselState = struct {
    x_m: f64,
    y_m: f64,
    heading_rad: f64,
    surge_mps: f64,
    sway_mps: f64,
    yaw_rate_radps: f64,
};

pub const StateFrame = struct {
    schema_version: []const u8 = schema_id,
    kind: []const u8 = state_kind,
    vessel_id: []const u8,
    session_id: []const u8,
    sequence: u64,
    sent_at_unix_ns: u64,
    simulation_time_ns: u64,
    state: VesselState,
};

pub const ThrusterCommand = struct {
    schema_version: []const u8,
    kind: []const u8,
    vessel_id: []const u8,
    session_id: []const u8,
    sequence: u64,
    telemetry_sequence: u64,
    issued_at_unix_ns: u64,
    thrust_n: []const f64,
};

pub fn encodeStateFrame(allocator: std.mem.Allocator, frame: StateFrame) Error![]u8 {
    try validateStateFrame(frame);
    const encoded = std.json.Stringify.valueAlloc(allocator, frame, .{}) catch return Error.OutOfMemory;
    errdefer allocator.free(encoded);
    if (encoded.len > max_payload_bytes) return Error.PayloadTooLarge;
    return encoded;
}

pub fn parseCommand(
    allocator: std.mem.Allocator,
    payload: []const u8,
) Error!std.json.Parsed(ThrusterCommand) {
    if (payload.len > max_payload_bytes) return Error.PayloadTooLarge;
    const parsed = std.json.parseFromSlice(ThrusterCommand, allocator, payload, .{
        .allocate = .alloc_always,
    }) catch |err| switch (err) {
        error.OutOfMemory => return Error.OutOfMemory,
        else => return Error.ParseFailed,
    };
    errdefer parsed.deinit();
    try validateCommand(parsed.value);
    return parsed;
}

pub fn validateStateFrame(frame: StateFrame) Error!void {
    if (!std.mem.eql(u8, frame.schema_version, schema_id) or
        !std.mem.eql(u8, frame.kind, state_kind)) return Error.InvalidEnvelope;
    try validateIdentifier(frame.vessel_id);
    try validateIdentifier(frame.session_id);
    inline for (.{
        frame.state.x_m,
        frame.state.y_m,
        frame.state.heading_rad,
        frame.state.surge_mps,
        frame.state.sway_mps,
        frame.state.yaw_rate_radps,
    }) |value| {
        if (!std.math.isFinite(value)) return Error.InvalidNumber;
    }
}

pub fn validateCommand(command: ThrusterCommand) Error!void {
    if (!std.mem.eql(u8, command.schema_version, schema_id) or
        !std.mem.eql(u8, command.kind, command_kind) or
        command.thrust_n.len == 0 or command.thrust_n.len > max_thrusters)
        return Error.InvalidEnvelope;
    try validateIdentifier(command.vessel_id);
    try validateIdentifier(command.session_id);
    for (command.thrust_n) |thrust| {
        if (!std.math.isFinite(thrust)) return Error.InvalidNumber;
    }
}

fn validateIdentifier(identifier: []const u8) Error!void {
    if (identifier.len == 0 or identifier.len > 128 or !std.ascii.isAlphanumeric(identifier[0]))
        return Error.InvalidIdentifier;
    for (identifier[1..]) |byte| {
        if (!(std.ascii.isAlphanumeric(byte) or byte == '.' or byte == '_' or byte == ':' or byte == '-'))
            return Error.InvalidIdentifier;
    }
}

test "state envelope encodes to the strict ArmadaClaw field contract" {
    const allocator = std.testing.allocator;
    const encoded = try encodeStateFrame(allocator, .{
        .vessel_id = "mercury-01",
        .session_id = "season-1778-a",
        .sequence = 7,
        .sent_at_unix_ns = 1_700_000_000_000_000_000,
        .simulation_time_ns = 70_000_000,
        .state = .{
            .x_m = 12.0,
            .y_m = -3.0,
            .heading_rad = 0.25,
            .surge_mps = 4.0,
            .sway_mps = -0.1,
            .yaw_rate_radps = 0.002,
        },
    });
    defer allocator.free(encoded);

    var parsed = try std.json.parseFromSlice(StateFrame, allocator, encoded, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(schema_id, parsed.value.schema_version);
    try std.testing.expectEqualStrings("mercury-01", parsed.value.vessel_id);
    try std.testing.expectEqual(@as(u64, 7), parsed.value.sequence);
}

test "thruster command produced by ArmadaClaw parses and validates" {
    const payload =
        \\{"schema_version":"yard.telemetry.v1","kind":"thruster_command","vessel_id":"mercury-01","session_id":"season-1778-a","sequence":3,"telemetry_sequence":7,"issued_at_unix_ns":1700000000000000000,"thrust_n":[0.0,5000.0,5000.0]}
    ;
    var parsed = try parseCommand(std.testing.allocator, payload);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 3), parsed.value.thrust_n.len);
    try std.testing.expectApproxEqAbs(@as(f64, 5000.0), parsed.value.thrust_n[1], 1e-9);
}

test "invalid identifiers and command schema are rejected" {
    try std.testing.expectError(Error.InvalidIdentifier, validateStateFrame(.{
        .vessel_id = "bad vessel",
        .session_id = "session-a",
        .sequence = 0,
        .sent_at_unix_ns = 0,
        .simulation_time_ns = 0,
        .state = .{ .x_m = 0, .y_m = 0, .heading_rad = 0, .surge_mps = 0, .sway_mps = 0, .yaw_rate_radps = 0 },
    }));

    const wrong_schema =
        \\{"schema_version":"yard.telemetry.v0","kind":"thruster_command","vessel_id":"mercury-01","session_id":"session-a","sequence":0,"telemetry_sequence":0,"issued_at_unix_ns":0,"thrust_n":[1.0]}
    ;
    try std.testing.expectError(Error.InvalidEnvelope, parseCommand(std.testing.allocator, wrong_schema));
}
