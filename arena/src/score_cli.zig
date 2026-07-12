//! Score a declarative submission against a trusted simulation result.
//! Usage: zig build score -- <mission.json> <submission.json> <simulation-result.json>

const std = @import("std");
const arena = @import("yard_arena");

pub fn main(init: std.process.Init) !u8 {
    return run(init) catch |err| {
        var stderr_buf: [1024]u8 = undefined;
        var stderr_w = std.Io.File.stderr().writer(init.io, &stderr_buf);
        const stderr = &stderr_w.interface;
        try stderr.print("yard-arena: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return 1;
    };
}

fn run(init: std.process.Init) !u8 {
    var memory = std.heap.ArenaAllocator.init(init.gpa);
    defer memory.deinit();
    const allocator = memory.allocator();

    var args: std.ArrayList([]const u8) = .empty;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    while (it.next()) |arg| try args.append(allocator, arg);
    if (args.items.len != 4) return error.InvalidArguments;

    const mission_bytes = try readFileAll(allocator, init.io, args.items[1]);
    const submission_bytes = try readFileAll(allocator, init.io, args.items[2]);
    const simulation_bytes = try readFileAll(allocator, init.io, args.items[3]);

    var mission_parsed = try std.json.parseFromSlice(arena.types.Mission, allocator, mission_bytes, .{});
    defer mission_parsed.deinit();
    var submission_parsed = try std.json.parseFromSlice(arena.types.Submission, allocator, submission_bytes, .{});
    defer submission_parsed.deinit();
    var simulation_parsed = try std.json.parseFromSlice(arena.types.SimulationResult, allocator, simulation_bytes, .{});
    defer simulation_parsed.deinit();

    const mission_sha256 = sha256Hex(mission_bytes);
    const submission_sha256 = sha256Hex(submission_bytes);
    const simulation_result_sha256 = sha256Hex(simulation_bytes);
    const run_id = runIdHex(&mission_sha256, &submission_sha256, &simulation_result_sha256);

    var scorecard = try arena.evaluator.evaluate(
        allocator,
        mission_parsed.value,
        submission_parsed.value,
        simulation_parsed.value,
        .{
            .run_id = &run_id,
            .mission_sha256 = &mission_sha256,
            .submission_sha256 = &submission_sha256,
            .simulation_result_sha256 = &simulation_result_sha256,
        },
    );
    defer arena.evaluator.deinitScorecard(allocator, &scorecard);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_w.interface;
    try std.json.Stringify.value(scorecard, .{ .whitespace = .indent_2 }, stdout);
    try stdout.writeByte('\n');
    try stdout.flush();
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

fn sha256Hex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

fn runIdHex(mission_sha256: []const u8, submission_sha256: []const u8, simulation_result_sha256: []const u8) [64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("yard-arena/run/v0\x00");
    hasher.update(mission_sha256);
    hasher.update("\x00");
    hasher.update(submission_sha256);
    hasher.update("\x00");
    hasher.update(simulation_result_sha256);
    hasher.update("\x00");
    hasher.update(arena.types.evaluator_version);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

test "SHA-256 hex is stable" {
    const digest = sha256Hex("yard");
    try std.testing.expectEqualStrings("6987c0b336f5f8cb05204b041a50849fa5f86fa7f0cc870e59c0352effe807d7", &digest);
}
