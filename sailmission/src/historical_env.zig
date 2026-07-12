//! Licensed historical weather ensemble consumed by the Mercury backend.

const std = @import("std");
const routing = @import("yard_routing");

pub const schema_id = "yard.arena.historical-environment.v0";

pub const Source = struct {
    title: []const u8,
    citation: []const u8,
    doi: []const u8,
    download_url: []const u8,
    license: []const u8,
    archive_sha256: []const u8,
    archive_member: []const u8,
    records_in_archive: u32,
};

pub const Selection = struct {
    year_min: i32,
    year_max: i32,
    route_corridor_nm: f64,
    selected_observations: u32,
    method: []const u8,
};

pub const Uncertainty = struct {
    model_id: []const u8,
    represented: []const []const u8,
    not_represented: []const []const u8,
    sampling: []const u8,
};

pub const RouteNode = struct {
    name: []const u8,
    lat_deg: f64,
    lon_deg: f64,
};

pub const MonthlyHistogram = struct {
    month: u8,
    observation_count: u32,
    joint_counts: []const u32,
};

pub const Leg = struct {
    leg_id: []const u8,
    course_bearing_deg: f64,
    route_nodes: []const RouteNode,
    monthly: []const MonthlyHistogram,
};

pub const Environment = struct {
    schema_version: []const u8,
    dataset_id: []const u8,
    source: Source,
    selection: Selection,
    uncertainty: Uncertainty,
    wind_speed_edges_mps: []const f64,
    relative_wind_angle_edges_deg: []const f64,
    legs: []const Leg,
};

pub const Sample = struct {
    wind_speed_mps: f64,
    relative_wind_angle_deg: f64,
    speed_bin: usize,
    angle_bin: usize,
    observation_count: u32,
};

pub const Error = error{ InvalidEnvironment, OutOfMemory, ParseFailed };

pub fn parse(allocator: std.mem.Allocator, json: []const u8) Error!std.json.Parsed(Environment) {
    const parsed = std.json.parseFromSlice(Environment, allocator, json, .{}) catch |err| switch (err) {
        error.OutOfMemory => return Error.OutOfMemory,
        else => return Error.ParseFailed,
    };
    errdefer parsed.deinit();
    try validate(parsed.value);
    return parsed;
}

pub fn validate(environment: Environment) Error!void {
    if (!std.mem.eql(u8, environment.schema_version, schema_id) or environment.dataset_id.len == 0)
        return Error.InvalidEnvironment;
    if (environment.source.archive_sha256.len != 64 or environment.source.records_in_archive == 0 or
        environment.selection.selected_observations == 0 or environment.selection.year_min > environment.selection.year_max or
        !std.math.isFinite(environment.selection.route_corridor_nm) or environment.selection.route_corridor_nm <= 0)
        return Error.InvalidEnvironment;
    if (environment.wind_speed_edges_mps.len < 2 or environment.relative_wind_angle_edges_deg.len < 2 or
        environment.legs.len == 0) return Error.InvalidEnvironment;
    try validateEdges(environment.wind_speed_edges_mps, 0.0, null);
    try validateEdges(environment.relative_wind_angle_edges_deg, 0.0, 180.0);
    const expected = (environment.wind_speed_edges_mps.len - 1) *
        (environment.relative_wind_angle_edges_deg.len - 1);
    for (environment.legs) |leg| {
        if (leg.leg_id.len == 0 or leg.route_nodes.len < 2 or leg.monthly.len != 12 or
            !std.math.isFinite(leg.course_bearing_deg)) return Error.InvalidEnvironment;
        var months_seen: [12]bool = [_]bool{false} ** 12;
        for (leg.monthly) |month| {
            if (month.month < 1 or month.month > 12 or months_seen[month.month - 1] or
                month.observation_count == 0 or month.joint_counts.len != expected)
                return Error.InvalidEnvironment;
            months_seen[month.month - 1] = true;
            var total: u64 = 0;
            for (month.joint_counts) |count| total += count;
            if (total != month.observation_count) return Error.InvalidEnvironment;
        }
    }
}

pub fn sample(environment: Environment, leg_index: usize, month_number: u8, category_u: f64, speed_u: f64, angle_u: f64) Error!Sample {
    if (leg_index >= environment.legs.len or month_number < 1 or month_number > 12)
        return Error.InvalidEnvironment;
    const leg = environment.legs[leg_index];
    const month = for (leg.monthly) |candidate| {
        if (candidate.month == month_number) break candidate;
    } else return Error.InvalidEnvironment;
    const speed_bins = environment.wind_speed_edges_mps.len - 1;
    const angle_bins = environment.relative_wind_angle_edges_deg.len - 1;
    const bounded = @min(@max(category_u, 0.0), 0.9999999999999999);
    const target: u64 = @intFromFloat(@floor(bounded * @as(f64, @floatFromInt(month.observation_count))));
    var cumulative: u64 = 0;
    var selected: usize = month.joint_counts.len - 1;
    for (month.joint_counts, 0..) |count, index| {
        cumulative += count;
        if (target < cumulative) {
            selected = index;
            break;
        }
    }
    const speed_bin = selected / angle_bins;
    const angle_bin = selected % angle_bins;
    if (speed_bin >= speed_bins) return Error.InvalidEnvironment;
    const speed_low = environment.wind_speed_edges_mps[speed_bin];
    const speed_high = environment.wind_speed_edges_mps[speed_bin + 1];
    const angle_low = environment.relative_wind_angle_edges_deg[angle_bin];
    const angle_high = environment.relative_wind_angle_edges_deg[angle_bin + 1];
    return .{
        .wind_speed_mps = speed_low + clampUnit(speed_u) * (speed_high - speed_low),
        .relative_wind_angle_deg = angle_low + clampUnit(angle_u) * (angle_high - angle_low),
        .speed_bin = speed_bin,
        .angle_bin = angle_bin,
        .observation_count = month.observation_count,
    };
}

pub fn legDistanceNm(leg: Leg) Error!f64 {
    var distance: f64 = 0;
    for (1..leg.route_nodes.len) |index| {
        const a = leg.route_nodes[index - 1];
        const b = leg.route_nodes[index];
        const metres = routing.great_circle.haversineDistanceM(
            std.math.degreesToRadians(a.lat_deg),
            std.math.degreesToRadians(a.lon_deg),
            std.math.degreesToRadians(b.lat_deg),
            std.math.degreesToRadians(b.lon_deg),
            routing.earth_radius_m,
        ) catch return Error.InvalidEnvironment;
        distance += metres / routing.nautical_mile_m;
    }
    return distance;
}

fn validateEdges(edges: []const f64, expected_min: f64, expected_max: ?f64) Error!void {
    if (edges[0] != expected_min) return Error.InvalidEnvironment;
    for (edges, 0..) |edge, index| {
        if (!std.math.isFinite(edge)) return Error.InvalidEnvironment;
        if (index > 0 and edge <= edges[index - 1]) return Error.InvalidEnvironment;
    }
    if (expected_max) |maximum| if (edges[edges.len - 1] != maximum) return Error.InvalidEnvironment;
}

fn clampUnit(value: f64) f64 {
    return @min(@max(value, 0.0), 0.9999999999999999);
}

test "empirical histogram sampling is deterministic and validates counts" {
    const counts = [_]u32{ 1, 3 };
    const months = [_]MonthlyHistogram{
        .{ .month = 1, .observation_count = 4, .joint_counts = &counts },
        .{ .month = 2, .observation_count = 4, .joint_counts = &counts },
        .{ .month = 3, .observation_count = 4, .joint_counts = &counts },
        .{ .month = 4, .observation_count = 4, .joint_counts = &counts },
        .{ .month = 5, .observation_count = 4, .joint_counts = &counts },
        .{ .month = 6, .observation_count = 4, .joint_counts = &counts },
        .{ .month = 7, .observation_count = 4, .joint_counts = &counts },
        .{ .month = 8, .observation_count = 4, .joint_counts = &counts },
        .{ .month = 9, .observation_count = 4, .joint_counts = &counts },
        .{ .month = 10, .observation_count = 4, .joint_counts = &counts },
        .{ .month = 11, .observation_count = 4, .joint_counts = &counts },
        .{ .month = 12, .observation_count = 4, .joint_counts = &counts },
    };
    const nodes = [_]RouteNode{
        .{ .name = "A", .lat_deg = 0, .lon_deg = 0 },
        .{ .name = "B", .lat_deg = 0, .lon_deg = 10 },
    };
    const represented = [_][]const u8{"sampling"};
    const environment: Environment = .{
        .schema_version = schema_id,
        .dataset_id = "fixture",
        .source = .{ .title = "x", .citation = "x", .doi = "x", .download_url = "x", .license = "CC-BY-3.0", .archive_sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .archive_member = "x", .records_in_archive = 4 },
        .selection = .{ .year_min = 1750, .year_max = 1805, .route_corridor_nm = 10, .selected_observations = 4, .method = "fixture" },
        .uncertainty = .{ .model_id = "fixture", .represented = &represented, .not_represented = &.{}, .sampling = "fixture" },
        .wind_speed_edges_mps = &.{ 0, 10, 20 },
        .relative_wind_angle_edges_deg = &.{ 0, 180 },
        .legs = &.{.{ .leg_id = "leg", .course_bearing_deg = 90, .route_nodes = &nodes, .monthly = &months }},
    };
    try validate(environment);
    const low = try sample(environment, 0, 1, 0.0, 0.5, 0.5);
    const high = try sample(environment, 0, 1, 0.9, 0.5, 0.5);
    try std.testing.expectEqual(@as(usize, 0), low.speed_bin);
    try std.testing.expectEqual(@as(usize, 1), high.speed_bin);
    try std.testing.expect((try legDistanceNm(environment.legs[0])) > 590.0);
}
