//! Deterministic SVG renderer for GZ stability curves.
//! Pure Zig — no GPU deps. Feeds multimodal dataset + CLI export.

const std = @import("std");

pub const GzPoint = struct {
    angle_deg: f64,
    gz_m: f64,
};

pub const IsCodeThresholds = struct {
    area_0_30_min: f64 = 0.055,
    area_0_40_min: f64 = 0.090,
    gz_at_30_min: f64 = 0.200,
    gm_0_min: f64 = 0.150,
};

pub const Style = struct {
    width: u32 = 640,
    height: u32 = 400,
    margin: u32 = 48,
    curve_color: []const u8 = "#1e88e5",
    grid_color: []const u8 = "#e0e0e0",
    threshold_color: []const u8 = "#e53935",
    bg_color: []const u8 = "#fafafa",
    title: []const u8 = "GZ Curve — Box Barge (wall-sided)",
};

pub const RenderInput = struct {
    points: []const GzPoint,
    gm0_m: f64,
    gm_corrected_m: f64,
    overall_pass: bool,
    thresholds: IsCodeThresholds = .{},
    style: Style = .{},
};

pub const Error = error{
    NoPoints,
    OutOfMemory,
};

fn appendFmt(
    list: *std.ArrayList(u8),
    gpa: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) Error!void {
    const s = try std.fmt.allocPrint(gpa, fmt, args);
    defer gpa.free(s);
    try list.appendSlice(gpa, s);
}

fn maxGz(points: []const GzPoint) f64 {
    var m: f64 = 0.0;
    for (points) |p| {
        if (p.gz_m > m) m = p.gz_m;
    }
    return if (m > 0.01) m else 0.5;
}

fn gzAt30(points: []const GzPoint) f64 {
    for (points) |p| {
        if (@abs(p.angle_deg - 30.0) < 0.01) return p.gz_m;
    }
    return 0.0;
}

/// Render a complete SVG document into `list`.
pub fn render(list: *std.ArrayList(u8), gpa: std.mem.Allocator, input: RenderInput) Error!void {
    if (input.points.len == 0) return Error.NoPoints;

    const style = input.style;
    const plot_w = style.width - 2 * style.margin;
    const plot_h = style.height - 2 * style.margin;
    const max_angle: f64 = 40.0;
    const max_gz = maxGz(input.points);
    const gz30 = gzAt30(input.points);
    const status = if (input.overall_pass) "PASS" else "FAIL";
    const status_color = if (input.overall_pass) "#43a047" else "#e53935";

    try appendFmt(list, gpa,
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{d}" height="{d}" viewBox="0 0 {d} {d}">
        \\  <rect width="100%" height="100%" fill="{s}"/>
        \\  <text x="{d}" y="24" font-family="monospace" font-size="14" fill="#212121">{s}</text>
        \\  <text x="{d}" y="40" font-family="monospace" font-size="11" fill="#616161">GM0={d:.3}m  GM_corr={d:.3}m  IS Code: <tspan fill="{s}">{s}</tspan></text>
    , .{
        style.width, style.height, style.width, style.height,
        style.bg_color,
        style.margin, style.title,
        style.margin, input.gm0_m, input.gm_corrected_m, status_color, status,
    });

    const x0 = style.margin;
    const y0 = style.margin + 16;
    try appendFmt(list, gpa,
        \\  <rect x="{d}" y="{d}" width="{d}" height="{d}" fill="white" stroke="#bdbdbd"/>
    , .{ x0, y0, plot_w, plot_h });

    var deg: f64 = 0.0;
    while (deg <= max_angle) : (deg += 10.0) {
        const px = x0 + @as(u32, @intFromFloat((deg / max_angle) * @as(f64, @floatFromInt(plot_w))));
        try appendFmt(list, gpa,
            \\  <line x1="{d}" y1="{d}" x2="{d}" y2="{d}" stroke="{s}" stroke-width="1"/>
            \\  <text x="{d}" y="{d}" font-family="monospace" font-size="10" fill="#757575" text-anchor="middle">{d:.0}°</text>
        , .{ px, y0, px, y0 + plot_h, style.grid_color, px, y0 + plot_h + 14, deg });
    }

    var gz_tick: f64 = 0.0;
    while (gz_tick <= max_gz + 0.001) : (gz_tick += max_gz / 5.0) {
        const py = y0 + plot_h - @as(u32, @intFromFloat((gz_tick / max_gz) * @as(f64, @floatFromInt(plot_h))));
        try appendFmt(list, gpa,
            \\  <line x1="{d}" y1="{d}" x2="{d}" y2="{d}" stroke="{s}" stroke-width="1"/>
            \\  <text x="{d}" y="{d}" font-family="monospace" font-size="10" fill="#757575" text-anchor="end">{d:.2}</text>
        , .{ x0, py, x0 + plot_w, py, style.grid_color, x0 - 4, py + 4, gz_tick });
    }

    const th_gz30_y = y0 + plot_h - @as(u32, @intFromFloat((input.thresholds.gz_at_30_min / max_gz) * @as(f64, @floatFromInt(plot_h))));
    try appendFmt(list, gpa,
        \\  <line x1="{d}" y1="{d}" x2="{d}" y2="{d}" stroke="{s}" stroke-width="1" stroke-dasharray="4,4"/>
        \\  <text x="{d}" y="{d}" font-family="monospace" font-size="9" fill="{s}">GZ@30° min {d:.2}m</text>
    , .{
        x0, th_gz30_y, x0 + plot_w, th_gz30_y, style.threshold_color,
        x0 + plot_w - 4, th_gz30_y - 4, style.threshold_color, input.thresholds.gz_at_30_min,
    });

    try list.appendSlice(gpa, "  <polyline fill=\"none\" stroke=\"");
    try list.appendSlice(gpa, style.curve_color);
    try list.appendSlice(gpa, "\" stroke-width=\"2.5\" points=\"");

    for (input.points, 0..) |p, i| {
        const px = x0 + @as(u32, @intFromFloat((p.angle_deg / max_angle) * @as(f64, @floatFromInt(plot_w))));
        const py = y0 + plot_h - @as(u32, @intFromFloat((p.gz_m / max_gz) * @as(f64, @floatFromInt(plot_h))));
        if (i > 0) try list.appendSlice(gpa, " ");
        try appendFmt(list, gpa, "{d},{d}", .{ px, py });
    }
    try list.appendSlice(gpa, "\"/>\n");

    const px30 = x0 + @as(u32, @intFromFloat((30.0 / max_angle) * @as(f64, @floatFromInt(plot_w))));
    const py30 = y0 + plot_h - @as(u32, @intFromFloat((gz30 / max_gz) * @as(f64, @floatFromInt(plot_h))));
    try appendFmt(list, gpa,
        \\  <circle cx="{d}" cy="{d}" r="5" fill="{s}"/>
        \\  <text x="{d}" y="{d}" font-family="monospace" font-size="10" fill="{s}">GZ@30°={d:.3}m</text>
    , .{ px30, py30, style.curve_color, px30 + 8, py30 - 8, style.curve_color, gz30 });

    try appendFmt(list, gpa,
        \\  <text x="{d}" y="{d}" font-family="monospace" font-size="12" fill="#424242" text-anchor="middle">Heel angle φ [deg]</text>
        \\  <text x="16" y="{d}" font-family="monospace" font-size="12" fill="#424242" text-anchor="middle" transform="rotate(-90 16 {d})">GZ [m]</text>
        \\</svg>
    , .{
        x0 + plot_w / 2, y0 + plot_h + 32,
        y0 + plot_h / 2, y0 + plot_h / 2,
    });
}

test "render produces valid SVG with polyline" {
    const points = [_]GzPoint{
        .{ .angle_deg = 0.0, .gz_m = 0.0 },
        .{ .angle_deg = 10.0, .gz_m = 0.08 },
        .{ .angle_deg = 20.0, .gz_m = 0.15 },
        .{ .angle_deg = 30.0, .gz_m = 0.22 },
        .{ .angle_deg = 40.0, .gz_m = 0.25 },
    };

    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try render(&list, std.testing.allocator, .{
        .points = &points,
        .gm0_m = 0.64,
        .gm_corrected_m = 0.46,
        .overall_pass = true,
    });

    try std.testing.expect(std.mem.indexOf(u8, list.items, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "<polyline") != null);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "PASS") != null);
}

test "empty points returns error" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const result = render(&list, std.testing.allocator, .{
        .points = &[_]GzPoint{},
        .gm0_m = 0.0,
        .gm_corrected_m = 0.0,
        .overall_pass = false,
    });
    try std.testing.expectError(Error.NoPoints, result);
}