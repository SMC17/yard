const std = @import("std");
const vvk = @import("yard_viz_vulkan");

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
        std.log.err("usage: render-scene <scene.json> [-o output.svg]", .{});
        return 1;
    }

    const json_path = args_buf.items[1];
    var out_path: []const u8 = "scene.svg";
    var i: usize = 2;
    while (i < args_buf.items.len) : (i += 1) {
        if (std.mem.eql(u8, args_buf.items[i], "-o") and i + 1 < args_buf.items.len) {
            out_path = args_buf.items[i + 1];
            i += 1;
        }
    }

    const json = readFileAll(allocator, init.io, json_path) catch |err| {
        std.log.err("cannot read {s}: {s}", .{ json_path, @errorName(err) });
        return 1;
    };

    const svg = try vvk.headless.renderSceneSvg(allocator, json);
    var out_file = try std.Io.Dir.cwd().createFile(init.io, out_path, .{});
    defer out_file.close(init.io);
    var write_buf: [4096]u8 = undefined;
    var writer = out_file.writer(init.io, &write_buf);
    try writer.interface.writeAll(svg);
    try writer.interface.flush();
    std.log.info("wrote {s} ({d} bytes)", .{ out_path, svg.len });
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