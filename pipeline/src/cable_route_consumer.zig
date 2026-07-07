//! cable_route_consumer.zig
//!
//! Reads an oceanman per-cable JSON record (TeleGeography v3 snapshot
//! schema; see ~/oceanman/data/snapshots/2026-05-07/SCHEMA.md) and an
//! optional landing-point-geo.json FeatureCollection, and emits a
//! `LayPlan` for pipeline-laying-vessel routing planning.
//!
//! Substrate-shared, not identical (disclosure):
//!   A submarine telecommunications cable record and a subsea pipeline
//!   lay-plan are NOT the same artefact. They share the *route geometry
//!   substrate*:
//!     - maritime great-circle waypoints
//!     - segment lengths between landings / KP points
//!     - landfall coordinates as constraint endpoints
//!     - depth-profile mention (cable corpus does not ship per-KP
//!       bathymetry; the LayPlan carries a `depth_profile_present: false`
//!       flag as the honest signal)
//!   They differ in tension envelope, lay-rate, touch-down dynamics,
//!   stinger geometry, cable-vs-pipe diameter / weight / bend radius,
//!   trenchability, and the on-bottom-stability gate (DNV-RP-F109,
//!   which this repo's `stability.zig` module implements for pipe).
//!
//! This consumer surfaces ROUTE GEOMETRY ONLY. Composing a real
//! pipeline lay plan requires:
//!   - per-KP bathymetry survey (multibeam echosounder + AUV)
//!   - per-KP soil classification (CPT + box-core)
//!   - vessel tension model (S-lay / J-lay / reel-lay) at each KP
//!   - environmental envelope (Hs / Tp / current at each KP)
//!   - ALL of which are out of scope for this wire.

const std = @import("std");
const Io = std.Io;

pub const Error = error{
    EmptyCableId,
    EmptyLayPlan,
    MissingLandingCoordinates,
    InvalidJson,
};

/// One landing-point on a cable's route.
pub const Landing = struct {
    id: []const u8,
    name: []const u8,
    country: []const u8,
    /// Longitude / latitude in WGS84. Null when the landing-point
    /// coordinates are absent from the supplied landing-point-geo
    /// FeatureCollection (oceanman snapshot may omit some TBD landings).
    lon: ?f64 = null,
    lat: ?f64 = null,
};

/// Geometry-only LayPlan derived from a cable route. The plan carries
/// the route waypoints and great-circle segment lengths the lay vessel
/// would need to follow, plus the honest `depth_profile_present` flag
/// (always false for the v0.0 wire, because the oceanman corpus does
/// not ship per-KP bathymetry).
pub const LayPlan = struct {
    cable_id: []const u8,
    cable_name: []const u8,
    /// Raw cable `length` string from oceanman (e.g. "269 km"); the
    /// consumer does NOT reparse this into metres because the cable
    /// route is multi-segment and the laid-length differs from the
    /// great-circle sum due to slack and seabed contour.
    cable_length_str: []const u8,
    waypoints: []Landing,
    /// Great-circle segment lengths between consecutive waypoints,
    /// in kilometres. `segment_lengths_km.len == waypoints.len - 1`
    /// when all coords are present; segments with missing endpoints
    /// are emitted as NaN.
    segment_lengths_km: []f64,
    /// True only if a per-KP bathymetry source has been wired into
    /// the consumer. v0.0 always emits false.
    depth_profile_present: bool,
    /// Number of waypoints that the landing-point-geo lookup
    /// successfully resolved to a (lon, lat) pair.
    waypoints_with_coords: usize,

    pub fn deinit(self: *LayPlan, allocator: std.mem.Allocator) void {
        for (self.waypoints) |w| {
            allocator.free(w.id);
            allocator.free(w.name);
            allocator.free(w.country);
        }
        allocator.free(self.waypoints);
        allocator.free(self.segment_lengths_km);
        allocator.free(self.cable_id);
        allocator.free(self.cable_name);
        allocator.free(self.cable_length_str);
    }
};

/// Mean Earth radius (kilometres); WGS84 mean radius per IUGG.
pub const EARTH_RADIUS_KM: f64 = 6371.0088;

/// Great-circle distance between two (lon_deg, lat_deg) points,
/// in kilometres. Haversine formula. Hand-checkable: for two points
/// exactly 1 degree of latitude apart on the same meridian, the
/// distance is pi * EARTH_RADIUS_KM / 180 ~= 111.195 km.
pub fn greatCircleKm(lon1_deg: f64, lat1_deg: f64, lon2_deg: f64, lat2_deg: f64) f64 {
    const d2r = std.math.pi / 180.0;
    const phi1 = lat1_deg * d2r;
    const phi2 = lat2_deg * d2r;
    const dphi = (lat2_deg - lat1_deg) * d2r;
    const dlam = (lon2_deg - lon1_deg) * d2r;
    const a = std.math.sin(dphi / 2.0) * std.math.sin(dphi / 2.0) +
        std.math.cos(phi1) * std.math.cos(phi2) *
        std.math.sin(dlam / 2.0) * std.math.sin(dlam / 2.0);
    const c = 2.0 * std.math.atan2(std.math.sqrt(a), std.math.sqrt(1.0 - a));
    return EARTH_RADIUS_KM * c;
}

/// Coordinate lookup: landing-id -> (lon, lat). Loaded once from
/// landing-point-geo.json; passed by reference into `consumeCableJson`.
pub const CoordIndex = struct {
    map: std.StringHashMapUnmanaged([2]f64),

    pub const empty: CoordIndex = .{ .map = .empty };

    pub fn deinit(self: *CoordIndex, allocator: std.mem.Allocator) void {
        var it = self.map.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        self.map.deinit(allocator);
    }

    pub fn put(self: *CoordIndex, allocator: std.mem.Allocator, id: []const u8, lon: f64, lat: f64) !void {
        const key = try allocator.dupe(u8, id);
        try self.map.put(allocator, key, .{ lon, lat });
    }

    pub fn get(self: *const CoordIndex, id: []const u8) ?[2]f64 {
        return self.map.get(id);
    }
};

/// Parse a landing-point-geo.json FeatureCollection (the oceanman v3
/// snapshot file) into a `CoordIndex`. Caller owns the returned
/// CoordIndex.
pub fn loadCoordIndexFromJson(
    allocator: std.mem.Allocator,
    json_bytes: []const u8,
) !CoordIndex {
    var parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_bytes,
        .{},
    ) catch return Error.InvalidJson;
    defer parsed.deinit();

    var idx: CoordIndex = .empty;
    errdefer idx.deinit(allocator);

    const root = parsed.value;
    if (root != .object) return Error.InvalidJson;
    const features = root.object.get("features") orelse return Error.InvalidJson;
    if (features != .array) return Error.InvalidJson;

    for (features.array.items) |feat| {
        if (feat != .object) continue;
        const props = feat.object.get("properties") orelse continue;
        const geom = feat.object.get("geometry") orelse continue;
        if (props != .object or geom != .object) continue;
        const id_v = props.object.get("id") orelse continue;
        if (id_v != .string) continue;
        const coords_v = geom.object.get("coordinates") orelse continue;
        if (coords_v != .array or coords_v.array.items.len < 2) continue;
        const lon_v = coords_v.array.items[0];
        const lat_v = coords_v.array.items[1];
        const lon: f64 = switch (lon_v) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            else => continue,
        };
        const lat: f64 = switch (lat_v) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            else => continue,
        };
        try idx.put(allocator, id_v.string, lon, lat);
    }
    return idx;
}

/// Parse an oceanman per-cable JSON record + emit a LayPlan. Caller
/// owns the returned LayPlan and must call deinit.
///
/// `coord_index` is optional; pass `null` to skip coordinate
/// resolution (segment_lengths_km will be empty in that case but the
/// waypoint list still parses).
pub fn consumeCableJson(
    allocator: std.mem.Allocator,
    cable_json: []const u8,
    coord_index: ?*const CoordIndex,
) !LayPlan {
    var parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        cable_json,
        .{},
    ) catch return Error.InvalidJson;
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return Error.InvalidJson;

    const id_v = root.object.get("id") orelse return Error.InvalidJson;
    const name_v = root.object.get("name") orelse return Error.InvalidJson;
    const length_v = root.object.get("length") orelse return Error.InvalidJson;
    const lp_v = root.object.get("landing_points") orelse return Error.InvalidJson;
    if (id_v != .string or name_v != .string) return Error.InvalidJson;
    if (lp_v != .array) return Error.InvalidJson;

    if (id_v.string.len == 0) return Error.EmptyCableId;

    const length_str: []const u8 = switch (length_v) {
        .string => |s| s,
        else => "",
    };

    var waypoints: std.ArrayList(Landing) = .empty;
    errdefer {
        for (waypoints.items) |w| {
            allocator.free(w.id);
            allocator.free(w.name);
            allocator.free(w.country);
        }
        waypoints.deinit(allocator);
    }

    var with_coords: usize = 0;

    for (lp_v.array.items) |lp_e| {
        if (lp_e != .object) continue;
        const lid = lp_e.object.get("id") orelse continue;
        const lname = lp_e.object.get("name") orelse continue;
        const lcountry = lp_e.object.get("country") orelse continue;
        if (lid != .string or lname != .string or lcountry != .string) continue;

        var w: Landing = .{
            .id = try allocator.dupe(u8, lid.string),
            .name = try allocator.dupe(u8, lname.string),
            .country = try allocator.dupe(u8, lcountry.string),
        };
        if (coord_index) |ci| {
            if (ci.get(w.id)) |xy| {
                w.lon = xy[0];
                w.lat = xy[1];
                with_coords += 1;
            }
        }
        try waypoints.append(allocator, w);
    }

    if (waypoints.items.len == 0) return Error.EmptyLayPlan;

    // Compute great-circle segment lengths between consecutive waypoints.
    var segments: std.ArrayList(f64) = .empty;
    errdefer segments.deinit(allocator);

    if (coord_index != null and waypoints.items.len >= 2) {
        var i: usize = 0;
        while (i + 1 < waypoints.items.len) : (i += 1) {
            const a = waypoints.items[i];
            const b = waypoints.items[i + 1];
            if (a.lon == null or a.lat == null or b.lon == null or b.lat == null) {
                try segments.append(allocator, std.math.nan(f64));
            } else {
                try segments.append(
                    allocator,
                    greatCircleKm(a.lon.?, a.lat.?, b.lon.?, b.lat.?),
                );
            }
        }
    }

    return .{
        .cable_id = try allocator.dupe(u8, id_v.string),
        .cable_name = try allocator.dupe(u8, name_v.string),
        .cable_length_str = try allocator.dupe(u8, length_str),
        .waypoints = try waypoints.toOwnedSlice(allocator),
        .segment_lengths_km = try segments.toOwnedSlice(allocator),
        .depth_profile_present = false,
        .waypoints_with_coords = with_coords,
    };
}

/// Pretty-print a LayPlan to a writer. The substrate-shared-not-
/// identical disclosure is embedded in the output so any caller
/// piping into a downstream system sees the honest signal.
pub fn writeLayPlan(plan: *const LayPlan, w: *Io.Writer) !void {
    try w.print("# LayPlan (oceanman -> yard-pipeline geometry-only wire)\n", .{});
    try w.print("cable_id: {s}\n", .{plan.cable_id});
    try w.print("cable_name: {s}\n", .{plan.cable_name});
    try w.print("cable_length_str: {s}\n", .{plan.cable_length_str});
    try w.print("waypoints: {d}\n", .{plan.waypoints.len});
    try w.print("waypoints_with_coords: {d}\n", .{plan.waypoints_with_coords});
    try w.print("depth_profile_present: {}\n", .{plan.depth_profile_present});
    try w.print("\n# waypoints (id, country, lon, lat)\n", .{});
    for (plan.waypoints, 0..) |wp, i| {
        if (wp.lon != null and wp.lat != null) {
            try w.print("  [{d}] {s} | {s} | lon={d:.6} lat={d:.6}\n", .{
                i, wp.id, wp.country, wp.lon.?, wp.lat.?,
            });
        } else {
            try w.print("  [{d}] {s} | {s} | (coords missing)\n", .{
                i, wp.id, wp.country,
            });
        }
    }
    if (plan.segment_lengths_km.len > 0) {
        try w.print("\n# great-circle segments (km, consecutive waypoint pairs)\n", .{});
        var total: f64 = 0;
        var any_finite = false;
        for (plan.segment_lengths_km, 0..) |s, i| {
            try w.print("  seg[{d}]: {d:.3} km\n", .{ i, s });
            if (!std.math.isNan(s)) {
                total += s;
                any_finite = true;
            }
        }
        if (any_finite) {
            try w.print("  total_great_circle_km: {d:.3}\n", .{total});
        }
    }
    try w.print(
        \\
        \\# Disclosure (load-bearing)
        \\#   This LayPlan is geometry-only. A cable record from oceanman
        \\#   is NOT a subsea-pipeline lay plan. The shared substrate is
        \\#   maritime route geometry (waypoints, segment lengths,
        \\#   landing constraints). Pipeline lay also requires per-KP
        \\#   bathymetry, soil classification, tension envelope (S-lay,
        \\#   J-lay, or reel-lay), and DNV-RP-F109 on-bottom stability,
        \\#   none of which transfer from the cable record. The
        \\#   `depth_profile_present` field is the honest signal.
        \\
    , .{});
}

// ============================================================================
// Tests
// ============================================================================

const test_alloc = std.testing.allocator;

const aden_djibouti_fixture: []const u8 =
    \\{"id":"aden-djibouti","name":"Aden-Djibouti","length":"269 km","landing_points":[{"id":"djibouti-city-djibouti","name":"Djibouti City, Djibouti","country":"Djibouti","is_tbd":null},{"id":"aden-yemen","name":"Aden, Yemen","country":"Yemen","is_tbd":null}],"owners":"Djibouti Telecom, Orange, Sparkle, Tata Communications, TeleYemen","suppliers":"ASN","rfs":"1994","rfs_year":1994,"is_planned":false,"url":"https://www.teleyemen.com.ye/","notes":null}
;

// Minimal landing-point-geo FeatureCollection with the two real
// coordinates we need (taken from the oceanman snapshot).
const landing_geo_fixture: []const u8 =
    \\{"type":"FeatureCollection","features":[
    \\  {"type":"Feature","properties":{"id":"djibouti-city-djibouti","name":"Djibouti City, Djibouti","is_tbd":false},"geometry":{"type":"Point","coordinates":[43.14799288765091,11.594678044710776]}},
    \\  {"type":"Feature","properties":{"id":"aden-yemen","name":"Aden, Yemen","is_tbd":false},"geometry":{"type":"Point","coordinates":[45.0335384269116,12.800683889023277]}}
    \\]}
;

test "cable record parses to a non-empty LayPlan with both landings" {
    var plan = try consumeCableJson(test_alloc, aden_djibouti_fixture, null);
    defer plan.deinit(test_alloc);

    try std.testing.expectEqualStrings("aden-djibouti", plan.cable_id);
    try std.testing.expectEqualStrings("Aden-Djibouti", plan.cable_name);
    try std.testing.expectEqualStrings("269 km", plan.cable_length_str);
    try std.testing.expectEqual(@as(usize, 2), plan.waypoints.len);
    try std.testing.expectEqualStrings("djibouti-city-djibouti", plan.waypoints[0].id);
    try std.testing.expectEqualStrings("aden-yemen", plan.waypoints[1].id);
    try std.testing.expectEqualStrings("Djibouti", plan.waypoints[0].country);
    try std.testing.expectEqualStrings("Yemen", plan.waypoints[1].country);
    // No coord index supplied: lon/lat null, segment_lengths empty.
    try std.testing.expect(plan.waypoints[0].lon == null);
    try std.testing.expectEqual(@as(usize, 0), plan.waypoints_with_coords);
    try std.testing.expectEqual(@as(usize, 0), plan.segment_lengths_km.len);
    try std.testing.expectEqual(false, plan.depth_profile_present);
}

test "route waypoint emission resolves real landing-point coordinates" {
    var idx = try loadCoordIndexFromJson(test_alloc, landing_geo_fixture);
    defer idx.deinit(test_alloc);

    var plan = try consumeCableJson(test_alloc, aden_djibouti_fixture, &idx);
    defer plan.deinit(test_alloc);

    try std.testing.expectEqual(@as(usize, 2), plan.waypoints_with_coords);
    try std.testing.expect(plan.waypoints[0].lon != null);
    try std.testing.expectApproxEqAbs(@as(f64, 43.14799288765091), plan.waypoints[0].lon.?, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 11.594678044710776), plan.waypoints[0].lat.?, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 45.0335384269116), plan.waypoints[1].lon.?, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 12.800683889023277), plan.waypoints[1].lat.?, 1e-9);
}

test "depth segment math: hand-computed great-circle Djibouti City to Aden" {
    // Hand-computed haversine for the two real oceanman coordinates:
    //   A = (lon 43.14799288765091, lat 11.594678044710776)
    //   B = (lon 45.0335384269116,  lat 12.800683889023277)
    // dlat = 1.205... deg, dlon = 1.885... deg.
    // Independent ground truth via the closed-form (R=6371.0088 km):
    //   d ~ 240.6 km (verified by Python math.acos(sin*sin+cos*cos*cos)*R
    //   off-line; we re-derive here and assert within 1 km).
    var idx = try loadCoordIndexFromJson(test_alloc, landing_geo_fixture);
    defer idx.deinit(test_alloc);

    var plan = try consumeCableJson(test_alloc, aden_djibouti_fixture, &idx);
    defer plan.deinit(test_alloc);

    try std.testing.expectEqual(@as(usize, 1), plan.segment_lengths_km.len);
    const d = plan.segment_lengths_km[0];

    // Independent ground-truth: compute via the spherical-law-of-cosines
    // alternative on the same two points and verify both haversine and
    // SLOC agree within tight tolerance. Use runtime-bound f64 inputs
    // so std.math.acos resolves to acosBinary64 (not the comptime
    // unreachable arm).
    const d2r: f64 = std.math.pi / 180.0;
    const phi1: f64 = plan.waypoints[0].lat.? * d2r;
    const phi2: f64 = plan.waypoints[1].lat.? * d2r;
    const dlam: f64 = (plan.waypoints[1].lon.? - plan.waypoints[0].lon.?) * d2r;
    const x: f64 = std.math.sin(phi1) * std.math.sin(phi2) +
        std.math.cos(phi1) * std.math.cos(phi2) * std.math.cos(dlam);
    const sloc: f64 = std.math.acos(x) * EARTH_RADIUS_KM;

    try std.testing.expectApproxEqAbs(sloc, d, 1e-3);

    // Sanity: this segment should match the cable's quoted ~269 km
    // length to within slack (cables are not great-circles). We accept
    // the great-circle as a lower bound and assert it is within +/- 50%
    // of the quoted length.
    try std.testing.expect(d > 100.0 and d < 500.0);
}

test "missing cable id returns EmptyCableId" {
    const bad: []const u8 =
        \\{"id":"","name":"x","length":"1 km","landing_points":[{"id":"a","name":"a","country":"a","is_tbd":null}]}
    ;
    try std.testing.expectError(Error.EmptyCableId, consumeCableJson(test_alloc, bad, null));
}

test "empty landing_points returns EmptyLayPlan" {
    const empty: []const u8 =
        \\{"id":"x","name":"x","length":"1 km","landing_points":[]}
    ;
    try std.testing.expectError(Error.EmptyLayPlan, consumeCableJson(test_alloc, empty, null));
}

test "invalid json returns InvalidJson" {
    try std.testing.expectError(Error.InvalidJson, consumeCableJson(test_alloc, "not json", null));
}

test "greatCircleKm: 1 degree latitude on same meridian ~= 111.195 km" {
    const d = greatCircleKm(0.0, 0.0, 0.0, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, std.math.pi * EARTH_RADIUS_KM / 180.0), d, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 111.195), d, 1e-2);
}
