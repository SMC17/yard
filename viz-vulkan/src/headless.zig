//! Phase 2 bridge: scene graph → SVG via yard-viz (no GPU required).

const std = @import("std");
const scene = @import("scene.zig");
const viz = @import("yard_viz");

pub const Error = error{
    ParseFailed,
    RenderFailed,
    OutOfMemory,
};

pub fn renderSceneSvg(allocator: std.mem.Allocator, json: []const u8) Error![]u8 {
    const sc = scene.parseSceneJson(allocator, json) catch return Error.ParseFailed;
    defer scene.freeScene(allocator, sc);
    const hull = sc.primaryHull();
    const kind: viz.hull_profile_svg.HullKind = if (std.mem.eql(u8, hull.kind, "wigley"))
        .wigley
    else
        .box_barge;
    return viz.hull_profile_svg.render(allocator, .{
        .kind = kind,
        .length = hull.length_m,
        .beam = hull.beam_m,
        .draft = hull.draft_m,
        .title = sc.title,
    }) catch return Error.RenderFailed;
}

test "headless scene JSON to SVG" {
    const json =
        \\{"title":"KCS Preview","hull":{"kind":"wigley","length_m":230.7,"beam_m":32.2,"draft_m":10.8}}
    ;
    const svg = try renderSceneSvg(std.testing.allocator, json);
    defer std.testing.allocator.free(svg);
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
}
