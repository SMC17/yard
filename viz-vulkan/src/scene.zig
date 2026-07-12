//! Fleet scene types for deterministic headless and Vulkan render paths.

const std = @import("std");

pub const HullMesh = struct {
    kind: []const u8,
    length_m: f64,
    beam_m: f64,
    draft_m: f64,
};

pub const Pose = struct {
    north_m: f64 = 0,
    east_m: f64 = 0,
    heave_m: f64 = 0,
    roll_rad: f64 = 0,
    pitch_rad: f64 = 0,
    yaw_rad: f64 = 0,
};

pub const Vessel = struct {
    id: []const u8,
    hull: HullMesh,
    pose: Pose = .{},
};

pub const Scene = struct {
    title: []const u8,
    simulation_time_s: f64 = 0,
    vessels: []const Vessel,

    pub fn primaryHull(self: Scene) HullMesh {
        return self.vessels[0].hull;
    }
};

pub const Error = error{
    InvalidJson,
    InvalidRoot,
    MissingHull,
    InvalidVessels,
    InvalidVessel,
    InvalidHull,
    InvalidPose,
    OutOfMemory,
};

/// Accepts the original single `hull` scene and the fleet `vessels` form.
/// Returned strings and vessel storage are owned by `allocator`.
pub fn parseSceneJson(allocator: std.mem.Allocator, json: []const u8) Error!Scene {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch return error.InvalidJson;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidRoot;
    const root = parsed.value.object;

    const title = try duplicateOptionalString(allocator, root.get("title"), "Yard Fleet Scene", error.InvalidRoot);
    errdefer allocator.free(title);
    const simulation_time_s = try optionalNumber(root.get("simulation_time_s"), 0, error.InvalidRoot);
    if (!std.math.isFinite(simulation_time_s) or simulation_time_s < 0) return error.InvalidRoot;

    if (root.get("vessels")) |value| {
        if (value != .array or value.array.items.len == 0) return error.InvalidVessels;
        const vessels = try allocator.alloc(Vessel, value.array.items.len);
        errdefer allocator.free(vessels);
        var initialized: usize = 0;
        errdefer freeVessels(allocator, vessels[0..initialized]);
        for (value.array.items, 0..) |item, index| {
            vessels[index] = try parseVessel(allocator, item, index);
            initialized += 1;
        }
        return .{
            .title = title,
            .simulation_time_s = simulation_time_s,
            .vessels = vessels,
        };
    }

    const hull_value = root.get("hull") orelse return error.MissingHull;
    const vessels = try allocator.alloc(Vessel, 1);
    errdefer allocator.free(vessels);
    const hull = try parseHull(allocator, hull_value);
    errdefer allocator.free(hull.kind);
    const id = try allocator.dupe(u8, "primary");
    vessels[0] = .{ .id = id, .hull = hull };
    return .{
        .title = title,
        .simulation_time_s = simulation_time_s,
        .vessels = vessels,
    };
}

pub fn freeScene(allocator: std.mem.Allocator, value: Scene) void {
    allocator.free(value.title);
    freeVessels(allocator, value.vessels);
    allocator.free(value.vessels);
}

fn parseVessel(allocator: std.mem.Allocator, value: std.json.Value, index: usize) Error!Vessel {
    if (value != .object) return error.InvalidVessel;
    const object = value.object;

    var default_id_buffer: [32]u8 = undefined;
    const default_id = std.fmt.bufPrint(&default_id_buffer, "vessel-{d}", .{index}) catch unreachable;
    const id = try duplicateOptionalString(allocator, object.get("id"), default_id, error.InvalidVessel);
    errdefer allocator.free(id);
    const hull = try parseHull(allocator, object.get("hull") orelse return error.InvalidVessel);
    errdefer allocator.free(hull.kind);
    const pose = if (object.get("pose")) |pose_value| try parsePose(pose_value) else Pose{};
    return .{ .id = id, .hull = hull, .pose = pose };
}

fn parseHull(allocator: std.mem.Allocator, value: std.json.Value) Error!HullMesh {
    if (value != .object) return error.InvalidHull;
    const object = value.object;
    const kind = try duplicateOptionalString(allocator, object.get("kind"), "box_barge", error.InvalidHull);
    errdefer allocator.free(kind);
    if (!std.mem.eql(u8, kind, "box_barge") and !std.mem.eql(u8, kind, "wigley"))
        return error.InvalidHull;

    const length_m = try optionalNumber(object.get("length_m"), 100, error.InvalidHull);
    const beam_m = try optionalNumber(object.get("beam_m"), 16, error.InvalidHull);
    const draft_m = try optionalNumber(object.get("draft_m"), 6, error.InvalidHull);
    if (!positiveFinite(length_m) or !positiveFinite(beam_m) or !positiveFinite(draft_m))
        return error.InvalidHull;
    if (beam_m > length_m or draft_m > beam_m) return error.InvalidHull;
    return .{ .kind = kind, .length_m = length_m, .beam_m = beam_m, .draft_m = draft_m };
}

fn parsePose(value: std.json.Value) Error!Pose {
    if (value != .object) return error.InvalidPose;
    const object = value.object;
    const pose: Pose = .{
        .north_m = try optionalNumber(object.get("north_m"), 0, error.InvalidPose),
        .east_m = try optionalNumber(object.get("east_m"), 0, error.InvalidPose),
        .heave_m = try optionalNumber(object.get("heave_m"), 0, error.InvalidPose),
        .roll_rad = try optionalNumber(object.get("roll_rad"), 0, error.InvalidPose),
        .pitch_rad = try optionalNumber(object.get("pitch_rad"), 0, error.InvalidPose),
        .yaw_rad = try optionalNumber(object.get("yaw_rad"), 0, error.InvalidPose),
    };
    inline for (std.meta.fields(Pose)) |field| {
        if (!std.math.isFinite(@field(pose, field.name))) return error.InvalidPose;
    }
    return pose;
}

fn duplicateOptionalString(
    allocator: std.mem.Allocator,
    value: ?std.json.Value,
    default: []const u8,
    invalid: Error,
) Error![]u8 {
    const source = if (value) |present| switch (present) {
        .string => |string| string,
        else => return invalid,
    } else default;
    if (source.len == 0 or source.len > 128) return invalid;
    return allocator.dupe(u8, source) catch error.OutOfMemory;
}

fn optionalNumber(value: ?std.json.Value, default: f64, invalid: Error) Error!f64 {
    if (value) |present| return switch (present) {
        .float => |number| number,
        .integer => |number| @floatFromInt(number),
        else => invalid,
    };
    return default;
}

fn positiveFinite(value: f64) bool {
    return std.math.isFinite(value) and value > 0;
}

fn freeVessels(allocator: std.mem.Allocator, vessels: []const Vessel) void {
    for (vessels) |vessel| {
        allocator.free(vessel.id);
        allocator.free(vessel.hull.kind);
    }
}

test "legacy scene parses as one vessel" {
    const json =
        \\{"title":"KCS Preview","hull":{"kind":"wigley","length_m":230.7,"beam_m":32.2,"draft_m":10.8}}
    ;
    const parsed = try parseSceneJson(std.testing.allocator, json);
    defer freeScene(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(usize, 1), parsed.vessels.len);
    try std.testing.expectEqualStrings("primary", parsed.vessels[0].id);
}

test "fleet scene preserves dynamic poses" {
    const json =
        \\{"title":"Formation","simulation_time_s":12.5,"vessels":[
        \\ {"id":"lead","hull":{"kind":"wigley","length_m":80,"beam_m":12,"draft_m":4},"pose":{"north_m":100,"yaw_rad":0.2}},
        \\ {"id":"wing","hull":{"kind":"box_barge","length_m":40,"beam_m":8,"draft_m":3},"pose":{"east_m":50,"roll_rad":0.1}}
        \\]}
    ;
    const parsed = try parseSceneJson(std.testing.allocator, json);
    defer freeScene(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(usize, 2), parsed.vessels.len);
    try std.testing.expectApproxEqAbs(@as(f64, 100), parsed.vessels[0].pose.north_m, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), parsed.vessels[1].pose.roll_rad, 1e-12);
}

test "invalid dimensions are rejected" {
    const json =
        \\{"hull":{"kind":"wigley","length_m":20,"beam_m":30,"draft_m":4}}
    ;
    try std.testing.expectError(error.InvalidHull, parseSceneJson(std.testing.allocator, json));
}
