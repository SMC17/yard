//! Scene graph types for deterministic render pipeline (JSON-serializable).

const std = @import("std");

pub const HullMesh = struct {
    kind: []const u8,
    length_m: f64,
    beam_m: f64,
    draft_m: f64,
};

pub const Overlay = struct {
    kind: []const u8,
    label: []const u8 = "",
};

pub const Scene = struct {
    title: []const u8,
    hull: HullMesh,
    overlays: []const Overlay = &.{},
};

pub fn parseSceneJson(allocator: std.mem.Allocator, json: []const u8) !Scene {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    const root = parsed.value.object;

    const title_owned = try allocator.dupe(u8, if (root.get("title")) |t| t.string else "Yard Scene");

    const hull_obj = root.get("hull") orelse return error.MissingHull;
    const hull = hull_obj.object;
    const kind_owned = try allocator.dupe(u8, if (hull.get("kind")) |k| k.string else "box_barge");

    return .{
        .title = title_owned,
        .hull = .{
            .kind = kind_owned,
            .length_m = if (hull.get("length_m")) |v| v.float else 100.0,
            .beam_m = if (hull.get("beam_m")) |v| v.float else 16.0,
            .draft_m = if (hull.get("draft_m")) |v| v.float else 6.0,
        },
    };
}

pub fn freeScene(allocator: std.mem.Allocator, scene: Scene) void {
    allocator.free(scene.title);
    allocator.free(scene.hull.kind);
}