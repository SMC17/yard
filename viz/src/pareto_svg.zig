//! SVG scatter plot for multi-objective Pareto fronts (power vs heave, GM labels).

const std = @import("std");

pub const Point = struct {
    power_kw: f64,
    heave_m: f64,
    gm_m: f64,
    label: []const u8 = "",
};

pub const Style = struct {
    width: u32 = 640,
    height: u32 = 480,
    margin: u32 = 56,
    title: []const u8 = "Pareto Front — Power vs Significant Heave",
    point_color: []const u8 = "#1565c0",
    front_color: []const u8 = "#e53935",
    bg_color: []const u8 = "#fafafa",
};

pub const RenderInput = struct {
    points: []const Point,
    /// Indices into points that lie on the Pareto front (optional hull polyline).
    front_indices: []const usize = &.{},
    style: Style = .{},
};

pub const Error = error{
    NoPoints,
    OutOfMemory,
};

fn appendFmt(list: *std.ArrayList(u8), gpa: std.mem.Allocator, comptime fmt: []const u8, args: anytype) Error!void {
    const s = try std.fmt.allocPrint(gpa, fmt, args);
    defer gpa.free(s);
    try list.appendSlice(gpa, s);
}

fn bounds(points: []const Point) struct { p_min: f64, p_max: f64, h_min: f64, h_max: f64 } {
    var p_min = points[0].power_kw;
    var p_max = points[0].power_kw;
    var h_min = points[0].heave_m;
    var h_max = points[0].heave_m;
    for (points[1..]) |pt| {
        p_min = @min(p_min, pt.power_kw);
        p_max = @max(p_max, pt.power_kw);
        h_min = @min(h_min, pt.heave_m);
        h_max = @max(h_max, pt.heave_m);
    }
    if (@abs(p_max - p_min) < 1.0) p_max = p_min + 1.0;
    if (@abs(h_max - h_min) < 0.01) h_max = h_min + 0.01;
    return .{ .p_min = p_min, .p_max = p_max, .h_min = h_min, .h_max = h_max };
}

pub fn render(list: *std.ArrayList(u8), gpa: std.mem.Allocator, input: RenderInput) Error!void {
    if (input.points.len == 0) return Error.NoPoints;
    const style = input.style;
    const b = bounds(input.points);
    const plot_w: f64 = @floatFromInt(style.width - 2 * style.margin);
    const plot_h: f64 = @floatFromInt(style.height - 2 * style.margin);
    const mx: f64 = @floatFromInt(style.margin);

    const x_map = struct {
        fn eval(p: f64, p_min: f64, p_max: f64, m: f64, w: f64) f64 {
            return m + (p - p_min) / (p_max - p_min) * w;
        }
    }.eval;
    const y_map = struct {
        fn eval(heave: f64, h_min: f64, h_max: f64, m: f64, ph: f64) f64 {
            return m + ph - (heave - h_min) / (h_max - h_min) * ph;
        }
    }.eval;

    try appendFmt(list, gpa,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{d}" height="{d}" viewBox="0 0 {d} {d}">
        \\  <rect width="100%" height="100%" fill="{s}"/>
        \\  <text x="{d}" y="28" font-family="monospace" font-size="14" fill="#212121">{s}</text>
        \\  <text x="{d}" y="{d}" font-family="monospace" font-size="11" fill="#616161">← Power [kW]</text>
        \\  <text x="12" y="{d}" font-family="monospace" font-size="11" fill="#616161" transform="rotate(-90 12 {d})">Heave [m] →</text>
    , .{
        style.width, style.height, style.width, style.height,
        style.bg_color,
        style.margin, style.title,
        style.margin, style.height - 12,
        style.margin + @as(u32, @intFromFloat(plot_h / 2.0)),
        style.margin + @as(u32, @intFromFloat(plot_h / 2.0)),
    });

    for (input.points, 0..) |pt, i| {
        const cx = x_map(pt.power_kw, b.p_min, b.p_max, mx, plot_w);
        const cy = y_map(pt.heave_m, b.h_min, b.h_max, mx, plot_h);
        const is_front = blk: {
            for (input.front_indices) |fi| {
                if (fi == i) break :blk true;
            }
            break :blk false;
        };
        const color = if (is_front) style.front_color else style.point_color;
        try appendFmt(list, gpa,
            \\  <circle cx="{d:.1}" cy="{d:.1}" r="5" fill="{s}" opacity="0.85"/>
        , .{ cx, cy, color });
    }

    if (input.front_indices.len >= 2) {
        try list.appendSlice(gpa, "  <polyline fill=\"none\" stroke=\"#e53935\" stroke-width=\"1.5\" opacity=\"0.6\" points=\"");
        for (input.front_indices) |fi| {
            const pt = input.points[fi];
            const cx = x_map(pt.power_kw, b.p_min, b.p_max, mx, plot_w);
            const cy = y_map(pt.heave_m, b.h_min, b.h_max, mx, plot_h);
            try appendFmt(list, gpa, "{d:.1},{d:.1} ", .{ cx, cy });
        }
        try list.appendSlice(gpa, "\"/>\n");
    }

    try appendFmt(list, gpa, "</svg>\n", .{});
}

test "pareto svg renders" {
    const pts = [_]Point{
        .{ .power_kw = 4000, .heave_m = 1.2, .gm_m = 1.5 },
        .{ .power_kw = 3500, .heave_m = 1.8, .gm_m = 2.0 },
        .{ .power_kw = 5000, .heave_m = 0.9, .gm_m = 0.8 },
    };
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try render(&list, std.testing.allocator, .{ .points = &pts, .front_indices = &[_]usize{ 0, 2 } });
    try std.testing.expect(std.mem.indexOf(u8, list.items, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "<circle") != null);
}