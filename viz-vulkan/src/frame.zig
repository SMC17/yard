//! Deterministic 3D fleet wireframe renderer shared by reference and Vulkan paths.

const std = @import("std");
const scene_mod = @import("scene.zig");

pub const background_rgba = [4]u8{ 18, 28, 40, 255 };

pub const Error = error{
    InvalidFrameSize,
    InvalidRgbaBuffer,
    OutOfMemory,
};

const Vec2 = struct { x: f64, y: f64 };
const Vec3 = struct { x: f64, y: f64, z: f64 };

const hull_edges = [_][2]u8{
    .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 4 }, .{ 4, 0 },
    .{ 5, 6 }, .{ 6, 7 }, .{ 7, 8 }, .{ 8, 9 }, .{ 9, 5 },
    .{ 0, 5 }, .{ 1, 6 }, .{ 2, 7 }, .{ 3, 8 }, .{ 4, 9 },
    .{ 0, 2 }, .{ 0, 4 },
};

const palette = [_][4]u8{
    .{ 51, 181, 229, 255 },
    .{ 237, 187, 64, 255 },
    .{ 108, 210, 142, 255 },
    .{ 231, 105, 122, 255 },
    .{ 173, 133, 232, 255 },
};

pub fn createReferenceRgba(
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
) Error![]u8 {
    const count = try byteCount(width, height);
    const pixels = allocator.alloc(u8, count) catch return error.OutOfMemory;
    for (0..count / 4) |index| {
        @memcpy(pixels[index * 4 ..][0..4], &background_rgba);
    }
    return pixels;
}

pub fn renderReferencePpm(
    allocator: std.mem.Allocator,
    value: scene_mod.Scene,
    width: u32,
    height: u32,
) Error![]u8 {
    const rgba = try createReferenceRgba(allocator, width, height);
    defer allocator.free(rgba);
    return renderPpmOnRgba(allocator, value, rgba, width, height);
}

/// Draws the same fleet geometry over an RGBA background supplied by either
/// the CPU reference path or Vulkan command-buffer readback.
pub fn renderPpmOnRgba(
    allocator: std.mem.Allocator,
    value: scene_mod.Scene,
    rgba: []u8,
    width: u32,
    height: u32,
) Error![]u8 {
    const expected = try byteCount(width, height);
    if (rgba.len != expected) return error.InvalidRgbaBuffer;

    const viewport = findViewport(value, width, height);
    drawWaterGrid(rgba, width, height, viewport);
    for (value.vessels, 0..) |vessel, vessel_index| {
        const vertices = hullVertices(vessel);
        const color = palette[vessel_index % palette.len];
        for (hull_edges) |edge| {
            const start = viewport.toPixel(project(vertices[edge[0]]));
            const end = viewport.toPixel(project(vertices[edge[1]]));
            drawLine(rgba, width, height, start[0], start[1], end[0], end[1], color);
        }
        const center = viewport.toPixel(project(.{
            .x = vessel.pose.north_m,
            .y = vessel.pose.east_m,
            .z = vessel.pose.heave_m + vessel.hull.beam_m * 0.35,
        }));
        const waterline = viewport.toPixel(project(.{
            .x = vessel.pose.north_m,
            .y = vessel.pose.east_m,
            .z = vessel.pose.heave_m,
        }));
        drawLine(rgba, width, height, waterline[0], waterline[1], center[0], center[1], color);
    }
    return encodePpm(allocator, rgba, width, height);
}

pub fn changedPixelCount(rgba: []const u8) usize {
    var changed: usize = 0;
    var offset: usize = 0;
    while (offset + 3 < rgba.len) : (offset += 4) {
        if (!std.mem.eql(u8, rgba[offset..][0..4], &background_rgba)) changed += 1;
    }
    return changed;
}

const Viewport = struct {
    center: Vec2,
    scale: f64,
    width: u32,
    height: u32,

    fn toPixel(self: Viewport, point: Vec2) [2]i32 {
        return .{
            @intFromFloat(@as(f64, @floatFromInt(self.width)) * 0.5 + (point.x - self.center.x) * self.scale),
            @intFromFloat(@as(f64, @floatFromInt(self.height)) * 0.5 - (point.y - self.center.y) * self.scale),
        };
    }
};

fn findViewport(value: scene_mod.Scene, width: u32, height: u32) Viewport {
    var min = Vec2{ .x = std.math.inf(f64), .y = std.math.inf(f64) };
    var max = Vec2{ .x = -std.math.inf(f64), .y = -std.math.inf(f64) };
    for (value.vessels) |vessel| {
        for (hullVertices(vessel)) |vertex| {
            const point = project(vertex);
            min.x = @min(min.x, point.x);
            min.y = @min(min.y, point.y);
            max.x = @max(max.x, point.x);
            max.y = @max(max.y, point.y);
        }
    }
    const span_x = @max(max.x - min.x, 1);
    const span_y = @max(max.y - min.y, 1);
    const scale_x = @as(f64, @floatFromInt(width)) * 0.78 / span_x;
    const scale_y = @as(f64, @floatFromInt(height)) * 0.72 / span_y;
    return .{
        .center = .{ .x = (min.x + max.x) * 0.5, .y = (min.y + max.y) * 0.5 },
        .scale = @min(scale_x, scale_y),
        .width = width,
        .height = height,
    };
}

fn hullVertices(vessel: scene_mod.Vessel) [10]Vec3 {
    const half_length = vessel.hull.length_m * 0.5;
    const half_beam = vessel.hull.beam_m * 0.5;
    const stern_beam = if (std.mem.eql(u8, vessel.hull.kind, "wigley")) half_beam * 0.35 else half_beam;
    const top = [_]Vec3{
        .{ .x = half_length, .y = 0, .z = 0 },
        .{ .x = half_length * 0.25, .y = half_beam, .z = 0 },
        .{ .x = -half_length, .y = stern_beam, .z = 0 },
        .{ .x = -half_length, .y = -stern_beam, .z = 0 },
        .{ .x = half_length * 0.25, .y = -half_beam, .z = 0 },
    };
    var result: [10]Vec3 = undefined;
    for (top, 0..) |point, index| {
        result[index] = transform(point, vessel.pose);
        result[index + 5] = transform(.{
            .x = point.x,
            .y = point.y * 0.42,
            .z = -vessel.hull.draft_m,
        }, vessel.pose);
    }
    return result;
}

fn transform(point: Vec3, pose: scene_mod.Pose) Vec3 {
    const sr = @sin(pose.roll_rad);
    const cr = @cos(pose.roll_rad);
    const sp = @sin(pose.pitch_rad);
    const cp = @cos(pose.pitch_rad);
    const sy = @sin(pose.yaw_rad);
    const cy = @cos(pose.yaw_rad);

    const rolled = Vec3{
        .x = point.x,
        .y = cr * point.y - sr * point.z,
        .z = sr * point.y + cr * point.z,
    };
    const pitched = Vec3{
        .x = cp * rolled.x + sp * rolled.z,
        .y = rolled.y,
        .z = -sp * rolled.x + cp * rolled.z,
    };
    return .{
        .x = cy * pitched.x - sy * pitched.y + pose.north_m,
        .y = sy * pitched.x + cy * pitched.y + pose.east_m,
        .z = pitched.z + pose.heave_m,
    };
}

fn project(point: Vec3) Vec2 {
    const camera_yaw = std.math.pi / 4.0;
    const camera_pitch = std.math.pi / 6.0;
    const cy = @cos(camera_yaw);
    const sy = @sin(camera_yaw);
    const cp = @cos(camera_pitch);
    const sp = @sin(camera_pitch);
    const along = sy * point.x + cy * point.y;
    return .{
        .x = cy * point.x - sy * point.y,
        .y = -sp * along + cp * point.z,
    };
}

fn drawWaterGrid(rgba: []u8, width: u32, height: u32, viewport: Viewport) void {
    const color = [4]u8{ 31, 55, 72, 255 };
    const extent = @as(f64, @floatFromInt(@max(width, height))) / viewport.scale;
    const step = extent / 8.0;
    var index: i32 = -8;
    while (index <= 8) : (index += 1) {
        const offset = @as(f64, @floatFromInt(index)) * step;
        const a = viewport.toPixel(project(.{ .x = -extent, .y = offset, .z = 0 }));
        const b = viewport.toPixel(project(.{ .x = extent, .y = offset, .z = 0 }));
        drawLine(rgba, width, height, a[0], a[1], b[0], b[1], color);
        const c = viewport.toPixel(project(.{ .x = offset, .y = -extent, .z = 0 }));
        const d = viewport.toPixel(project(.{ .x = offset, .y = extent, .z = 0 }));
        drawLine(rgba, width, height, c[0], c[1], d[0], d[1], color);
    }
}

fn drawLine(
    rgba: []u8,
    width: u32,
    height: u32,
    x_start: i32,
    y_start: i32,
    x_end: i32,
    y_end: i32,
    color: [4]u8,
) void {
    var x = x_start;
    var y = y_start;
    const dx: i32 = @intCast(@abs(x_end - x_start));
    const dy: i32 = @intCast(@abs(y_end - y_start));
    const sx: i32 = if (x_start < x_end) 1 else -1;
    const sy: i32 = if (y_start < y_end) 1 else -1;
    var line_error = dx - dy;
    while (true) {
        putPixel(rgba, width, height, x, y, color);
        if (x == x_end and y == y_end) break;
        const doubled = line_error * 2;
        if (doubled > -dy) {
            line_error -= dy;
            x += sx;
        }
        if (doubled < dx) {
            line_error += dx;
            y += sy;
        }
    }
}

fn putPixel(rgba: []u8, width: u32, height: u32, x: i32, y: i32, color: [4]u8) void {
    if (x < 0 or y < 0 or x >= width or y >= height) return;
    const ux: usize = @intCast(x);
    const uy: usize = @intCast(y);
    const offset = (uy * width + ux) * 4;
    @memcpy(rgba[offset..][0..4], &color);
}

fn encodePpm(
    allocator: std.mem.Allocator,
    rgba: []const u8,
    width: u32,
    height: u32,
) Error![]u8 {
    var header_buffer: [64]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buffer, "P6\n{d} {d}\n255\n", .{ width, height }) catch unreachable;
    const rgb_count = std.math.mul(usize, width, height * 3) catch return error.InvalidFrameSize;
    const output = allocator.alloc(u8, header.len + rgb_count) catch return error.OutOfMemory;
    @memcpy(output[0..header.len], header);
    var source: usize = 0;
    var destination = header.len;
    while (source < rgba.len) : (source += 4) {
        @memcpy(output[destination..][0..3], rgba[source..][0..3]);
        destination += 3;
    }
    return output;
}

fn byteCount(width: u32, height: u32) Error!usize {
    if (width < 64 or height < 64 or width > 4096 or height > 4096)
        return error.InvalidFrameSize;
    const pixels = std.math.mul(usize, width, height) catch return error.InvalidFrameSize;
    return std.math.mul(usize, pixels, 4) catch return error.InvalidFrameSize;
}

test "fleet frame is deterministic and nonblank" {
    const json =
        \\{"title":"Formation","simulation_time_s":12.5,"vessels":[
        \\ {"id":"lead","hull":{"kind":"wigley","length_m":80,"beam_m":12,"draft_m":4},"pose":{"north_m":30,"yaw_rad":0.2,"roll_rad":0.08}},
        \\ {"id":"wing","hull":{"kind":"box_barge","length_m":40,"beam_m":8,"draft_m":3},"pose":{"north_m":-30,"east_m":45,"yaw_rad":-0.25}}
        \\]}
    ;
    const parsed = try scene_mod.parseSceneJson(std.testing.allocator, json);
    defer scene_mod.freeScene(std.testing.allocator, parsed);
    const rgba = try createReferenceRgba(std.testing.allocator, 320, 180);
    defer std.testing.allocator.free(rgba);
    const first = try renderPpmOnRgba(std.testing.allocator, parsed, rgba, 320, 180);
    defer std.testing.allocator.free(first);
    const second = try renderReferencePpm(std.testing.allocator, parsed, 320, 180);
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualSlices(u8, first, second);
    try std.testing.expect(std.mem.startsWith(u8, first, "P6\n320 180\n255\n"));
    try std.testing.expect(changedPixelCount(rgba) > 500);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(first, &digest, .{});
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    try std.testing.expectEqualStrings(
        "96ef989f3e952a08e430a549ecf0aa05ed1396d2256f6a2bea53e387b31fc758",
        &digest_hex,
    );
}
