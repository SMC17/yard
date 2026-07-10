//! Deterministic 2D hull profile SVG (waterline + midship section).

const std = @import("std");

pub const HullKind = enum {
    box_barge,
    wigley,
};

pub const Input = struct {
    kind: HullKind,
    length: f64,
    beam: f64,
    draft: f64,
    width: u32 = 640,
    height: u32 = 320,
    title: []const u8 = "Hull Profile",
};

pub const Error = error{OutOfMemory};

pub fn render(allocator: std.mem.Allocator, input: Input) Error![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    const w = input.width;
    const h = input.height;
    const margin: u32 = 40;
    const plot_w = w - 2 * margin;
    const plot_h = h - 2 * margin;

    try appendFmt(&buf, allocator, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{d}\" height=\"{d}\" viewBox=\"0 0 {d} {d}\">\n", .{ w, h, w, h });
    try appendFmt(&buf, allocator, "<rect width=\"{d}\" height=\"{d}\" fill=\"#fafafa\"/>\n", .{ w, h });
    try appendFmt(&buf, allocator, "<text x=\"{d}\" y=\"24\" font-size=\"14\" fill=\"#333\">{s}</text>\n", .{ margin, input.title });

    const scale_y = @as(f64, @floatFromInt(plot_h)) / @max(input.beam, input.draft);

    // Waterline (plan view) — top half of canvas.
    const wl_y0: u32 = margin + plot_h / 4;
    try appendFmt(&buf, allocator, "<polyline fill=\"none\" stroke=\"#1565c0\" stroke-width=\"2\" points=\"", .{});

    var i: u32 = 0;
    while (i <= 40) : (i += 1) {
        const x_frac = @as(f64, @floatFromInt(i)) / 40.0;
        const x_ship = (x_frac - 0.5) * input.length;
        const half_b = switch (input.kind) {
            .box_barge => input.beam / 2.0,
            .wigley => blk: {
                const xi = 2.0 * x_ship / input.length;
                break :blk (input.beam / 2.0) * (1.0 - xi * xi);
            },
        };
        const px = margin + @as(u32, @intFromFloat(x_frac * @as(f64, @floatFromInt(plot_w))));
        const py = wl_y0 + @as(u32, @intFromFloat((input.beam / 2.0 - half_b) * scale_y));
        try appendFmt(&buf, allocator, "{d},{d} ", .{ px, py });
    }
    try buf.appendSlice(allocator, "\"/>\n");

    // Midship section — bottom half.
    const sec_x0 = margin + plot_w / 2;
    const sec_y0 = margin + plot_h / 2 + 20;
    try appendFmt(&buf, allocator, "<polyline fill=\"none\" stroke=\"#2e7d32\" stroke-width=\"2\" points=\"", .{});

    i = 0;
    while (i <= 20) : (i += 1) {
        const z_frac = @as(f64, @floatFromInt(i)) / 20.0;
        const z = z_frac * input.draft;
        const half_b = switch (input.kind) {
            .box_barge => input.beam / 2.0,
            .wigley => blk: {
                const zi = z / input.draft;
                break :blk (input.beam / 2.0) * (1.0 - zi * zi);
            },
        };
        const px = sec_x0 + @as(u32, @intFromFloat(half_b * scale_y));
        const py = sec_y0 + @as(u32, @intFromFloat(z_frac * @as(f64, @floatFromInt(plot_h / 2))));
        try appendFmt(&buf, allocator, "{d},{d} ", .{ px, py });
    }
    try buf.appendSlice(allocator, "\"/>\n");
    try buf.appendSlice(allocator, "</svg>\n");
    return buf.toOwnedSlice(allocator);
}

fn appendFmt(list: *std.ArrayList(u8), gpa: std.mem.Allocator, comptime fmt: []const u8, args: anytype) Error!void {
    const s = try std.fmt.allocPrint(gpa, fmt, args);
    defer gpa.free(s);
    try list.appendSlice(gpa, s);
}

test "wigley profile SVG non-empty" {
    const svg = try render(std.testing.allocator, .{
        .kind = .wigley,
        .length = 100.0,
        .beam = 10.0,
        .draft = 6.25,
    });
    defer std.testing.allocator.free(svg);
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(svg.len > 200);
}