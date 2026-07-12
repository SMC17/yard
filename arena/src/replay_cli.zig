//! Verify a replay NDJSON chain and optionally its committed head.

const std = @import("std");
const arena = @import("yard_arena");

pub fn main(init: std.process.Init) !u8 {
    return run(init) catch |err| {
        var buffer: [1024]u8 = undefined;
        var writer = std.Io.File.stderr().writer(init.io, &buffer);
        try writer.interface.print("yard-arena-replay: {s}\n", .{@errorName(err)});
        try writer.interface.flush();
        return 1;
    };
}

fn run(init: std.process.Init) !u8 {
    var memory = std.heap.ArenaAllocator.init(init.gpa);
    defer memory.deinit();
    const allocator = memory.allocator();
    var arguments: std.ArrayList([]const u8) = .empty;
    var iterator = try init.minimal.args.iterateAllocator(allocator);
    defer iterator.deinit();
    while (iterator.next()) |argument| try arguments.append(allocator, argument);
    if (arguments.items.len != 3 and arguments.items.len != 5) return error.InvalidArguments;
    if (!std.mem.eql(u8, arguments.items[1], "verify")) return error.InvalidArguments;
    var expected_head: ?[]const u8 = null;
    if (arguments.items.len == 5) {
        if (!std.mem.eql(u8, arguments.items[3], "--head")) return error.InvalidArguments;
        expected_head = arguments.items[4];
    }

    const bytes = try readFileAll(allocator, init.io, arguments.items[2]);
    var events: std.ArrayList(arena.replay.Event) = .empty;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const parsed = try std.json.parseFromSlice(arena.replay.Event, allocator, line, .{});
        try events.append(allocator, parsed.value);
    }
    if (events.items.len == 0 or !arena.replay.verify(events.items)) return error.InvalidReplay;
    const head = events.items[events.items.len - 1].event_sha256;
    if (expected_head) |expected| if (!std.mem.eql(u8, expected, head)) return error.HeadMismatch;

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    try writer.interface.print(
        "{{\"valid\":true,\"algorithm\":\"{s}\",\"events\":{d},\"head_sha256\":\"{s}\"}}\n",
        .{ arena.replay.algorithm_id, events.items.len, head },
    );
    try writer.interface.flush();
    return 0;
}

fn readFileAll(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const stat = try file.stat(io);
    const bytes = try allocator.alloc(u8, stat.size);
    var read_buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    var offset: usize = 0;
    while (offset < bytes.len) {
        const count = try reader.interface.readSliceShort(bytes[offset..]);
        if (count == 0) break;
        offset += count;
    }
    if (offset != bytes.len) return error.UnexpectedEndOfFile;
    return bytes;
}
