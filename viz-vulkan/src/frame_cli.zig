const std = @import("std");
const viewer = @import("yard_viz_vulkan");

pub fn main(init: std.process.Init) !u8 {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(allocator);
    var iterator = try init.minimal.args.iterateAllocator(allocator);
    defer iterator.deinit();
    while (iterator.next()) |arg| try args.append(allocator, arg);
    if (args.items.len != 4 or !std.mem.eql(u8, args.items[2], "-o")) {
        std.log.err("usage: render-frame <scene.json> -o <frame.ppm>", .{});
        return 1;
    }

    const json = readFileAll(allocator, init.io, args.items[1]) catch |err| {
        std.log.err("cannot read {s}: {s}", .{ args.items[1], @errorName(err) });
        return 1;
    };
    const parsed = viewer.scene.parseSceneJson(allocator, json) catch |err| {
        std.log.err("invalid scene: {s}", .{@errorName(err)});
        return 1;
    };
    const ppm = viewer.frame.renderReferencePpm(allocator, parsed, 960, 540) catch |err| {
        std.log.err("reference frame failed: {s}", .{@errorName(err)});
        return 1;
    };

    var output = try std.Io.Dir.cwd().createFile(init.io, args.items[3], .{});
    defer output.close(init.io);
    var write_buffer: [8192]u8 = undefined;
    var writer = output.writer(init.io, &write_buffer);
    try writer.interface.writeAll(ppm);
    try writer.interface.flush();
    std.log.info("wrote {s} ({d} bytes, {d} vessels)", .{ args.items[3], ppm.len, parsed.vessels.len });
    return 0;
}

fn readFileAll(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const stat = try file.stat(io);
    const buffer = try allocator.alloc(u8, stat.size);
    var read_buffer: [8192]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    var offset: usize = 0;
    while (offset < buffer.len) {
        const count = try reader.interface.readSliceShort(buffer[offset..]);
        if (count == 0) break;
        offset += count;
    }
    return buffer[0..offset];
}
