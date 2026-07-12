//! CLI: yard-historical-conflict <scenario.json> [--replay replay.jsonl]

const std = @import("std");
const lib = @import("yard_historical_conflict");

const max_scenario_bytes = 8 * 1024 * 1024;

pub fn main(init: std.process.Init) !u8 {
    return run(init) catch |err| {
        var buffer: [1024]u8 = undefined;
        var stderr = std.Io.File.stderr().writer(init.io, &buffer);
        try stderr.interface.print("yard-historical-conflict: {s}\n", .{@errorName(err)});
        try stderr.interface.flush();
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
    if (arguments.items.len != 2 and arguments.items.len != 4) return error.InvalidArguments;
    var replay_path: ?[]const u8 = null;
    if (arguments.items.len == 4) {
        if (!std.mem.eql(u8, arguments.items[2], "--replay")) return error.InvalidArguments;
        replay_path = arguments.items[3];
    }

    const bytes = try readFileAll(allocator, init.io, arguments.items[1]);
    var parsed = try std.json.parseFromSlice(lib.types.Scenario, allocator, bytes, .{});
    defer parsed.deinit();
    var violations_buffer: [lib.policy.max_violations]lib.policy.Violation = undefined;
    const violations = try lib.policy.validate(parsed.value, &violations_buffer);
    if (violations.len != 0) {
        var buffer: [2048]u8 = undefined;
        var stderr = std.Io.File.stderr().writer(init.io, &buffer);
        for (violations) |violation| try stderr.interface.print("policy: {s}: {s}\n", .{ @tagName(violation.code), violation.subject });
        try stderr.interface.flush();
        return 2;
    }

    var scenario_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &scenario_digest, .{});
    const result = try lib.simulation.simulateBound(
        allocator,
        parsed.value,
        std.fmt.bytesToHex(scenario_digest, .lower),
    );
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try std.json.Stringify.value(.{ .summary = result.summary, .outcomes = result.outcomes }, .{ .whitespace = .indent_2 }, &stdout.interface);
    try stdout.interface.writeByte('\n');
    try stdout.interface.flush();

    if (replay_path) |path| {
        var file = try std.Io.Dir.cwd().createFile(init.io, path, .{});
        defer file.close(init.io);
        var buffer: [8192]u8 = undefined;
        var writer = file.writer(init.io, &buffer);
        for (result.replay_events) |*event| {
            try std.json.Stringify.value(event.view(), .{}, &writer.interface);
            try writer.interface.writeByte('\n');
        }
        try writer.interface.flush();
    }
    return 0;
}

fn readFileAll(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const stat = try file.stat(io);
    if (stat.size > max_scenario_bytes) return error.FileTooLarge;
    const bytes = try allocator.alloc(u8, stat.size);
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    var offset: usize = 0;
    while (offset < bytes.len) {
        const count = try reader.interface.readSliceShort(bytes[offset..]);
        if (count == 0) break;
        offset += count;
    }
    if (offset != bytes.len) return error.UnexpectedEndOfFile;
    return bytes;
}
