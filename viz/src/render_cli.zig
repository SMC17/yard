//! CLI: render GZ curve SVG from oracle JSON input.
//! Usage: zig build render-gz -- input.json -o curve.svg

const std = @import("std");
const viz = @import("yard_viz");

const InputJson = struct {
    gm0_m: f64,
    gm_corrected_m: f64,
    overall: []const u8,
    gz_curve: []const struct {
        angle_deg: f64,
        gz_m: f64,
    },
};

pub fn main(init: std.process.Init) !u8 {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args_buf: std.ArrayList([]const u8) = .empty;
    defer args_buf.deinit(allocator);

    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    while (it.next()) |a| try args_buf.append(allocator, a);

    if (args_buf.items.len < 2) {
        std.log.err("usage: render-gz <input.json> [-o output.svg]", .{});
        return 1;
    }

    const input_path = args_buf.items[1];
    var output_path: []const u8 = "gz_curve.svg";
    var i: usize = 2;
    while (i < args_buf.items.len) : (i += 1) {
        if (std.mem.eql(u8, args_buf.items[i], "-o") and i + 1 < args_buf.items.len) {
            output_path = args_buf.items[i + 1];
            i += 1;
        }
    }

    const json_bytes = readFileAll(allocator, init.io, input_path) catch |err| {
        std.log.err("cannot read {s}: {s}", .{ input_path, @errorName(err) });
        return 1;
    };

    const parsed = try std.json.parseFromSlice(InputJson, allocator, json_bytes, .{});
    defer parsed.deinit();

    const data = parsed.value;
    var points = try allocator.alloc(viz.gz_svg.GzPoint, data.gz_curve.len);
    for (data.gz_curve, 0..) |s, j| {
        points[j] = .{ .angle_deg = s.angle_deg, .gz_m = s.gz_m };
    }

    var svg_buf: std.ArrayList(u8) = .empty;
    defer svg_buf.deinit(allocator);
    try viz.gz_svg.render(&svg_buf, allocator, .{
        .points = points,
        .gm0_m = data.gm0_m,
        .gm_corrected_m = data.gm_corrected_m,
        .overall_pass = std.mem.eql(u8, data.overall, "PASS"),
    });

    var out_file = try std.Io.Dir.cwd().createFile(init.io, output_path, .{});
    defer out_file.close(init.io);
    try out_file.writeAll(init.io, svg_buf.items);
    std.log.info("wrote {s} ({d} bytes)", .{ output_path, svg_buf.items.len });
    return 0;
}

fn readFileAll(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    var f = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer f.close(io);
    const st = try f.stat(io);
    const buf = try allocator.alloc(u8, st.size);
    errdefer allocator.free(buf);
    var read_buf: [4096]u8 = undefined;
    var reader = f.reader(io, &read_buf);
    var iface = &reader.interface;
    var off: usize = 0;
    while (off < buf.len) {
        const n = try iface.readSliceShort(buf[off..]);
        if (n == 0) break;
        off += n;
    }
    return buf[0..off];
}