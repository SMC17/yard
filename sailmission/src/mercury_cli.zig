//! Generate trusted Mercury results for public/reference and hosted runs.

const std = @import("std");
const lib = @import("yard_sailmission");

pub fn main(init: std.process.Init) !u8 {
    return run(init) catch |err| {
        var buffer: [1024]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(init.io, &buffer);
        try stderr_writer.interface.print("yard-mercury: {s}\n", .{@errorName(err)});
        try stderr_writer.interface.flush();
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
    const args = arguments.items;
    if (args.len < 2) return error.InvalidArguments;
    if (std.mem.eql(u8, args[1], "eval")) return runLegacy(init, allocator, args);
    if (std.mem.eql(u8, args[1], "evaluate")) return runHosted(init, allocator, args);
    if (std.mem.eql(u8, args[1], "pack-hidden")) return packHidden(init, allocator, args);
    return error.InvalidArguments;
}

fn runLegacy(init: std.process.Init, allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    if (args.len < 6) return error.InvalidArguments;

    var seed_override: ?u64 = null;
    var output_path: ?[]const u8 = null;
    var replay_path: ?[]const u8 = null;
    var index: usize = 6;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--seed") and index + 1 < args.len) {
            seed_override = try std.fmt.parseInt(u64, args[index + 1], 10);
            index += 1;
        } else if (std.mem.eql(u8, args[index], "--output") and index + 1 < args.len) {
            output_path = args[index + 1];
            index += 1;
        } else if (std.mem.eql(u8, args[index], "--replay") and index + 1 < args.len) {
            replay_path = args[index + 1];
            index += 1;
        } else return error.InvalidArguments;
    }
    const replay_file_path = replay_path orelse return error.InvalidArguments;

    const mission_bytes = try readFileAll(allocator, init.io, args[2]);
    const submission_bytes = try readFileAll(allocator, init.io, args[3]);
    const environment_bytes = try readFileAll(allocator, init.io, args[4]);
    const config_bytes = try readFileAll(allocator, init.io, args[5]);
    var mission = try std.json.parseFromSlice(lib.arena.types.Mission, allocator, mission_bytes, .{});
    defer mission.deinit();
    var submission = try std.json.parseFromSlice(lib.arena.types.Submission, allocator, submission_bytes, .{});
    defer submission.deinit();
    const environment = try lib.historical_env.parse(allocator, environment_bytes);
    defer environment.deinit();
    const config = try lib.mercury.parseConfig(allocator, config_bytes);
    defer config.deinit();
    if (mission.value.rng.public_seeds.len == 0) return error.InvalidMission;
    const seed = seed_override orelse mission.value.rng.public_seeds[0];

    const mission_sha = sha256Hex(mission_bytes);
    const submission_sha = sha256Hex(submission_bytes);
    const environment_sha = compositeEnvironmentSha(environment_bytes, config_bytes);
    const evaluated = try lib.mercury.evaluate(
        allocator,
        mission.value,
        submission.value,
        environment.value,
        config.value,
        &mission_sha,
        &submission_sha,
        &environment_sha,
        seed,
    );

    if (output_path) |path| {
        var file = try std.Io.Dir.cwd().createFile(init.io, path, .{});
        defer file.close(init.io);
        var buffer: [4096]u8 = undefined;
        var writer = file.writer(init.io, &buffer);
        try std.json.Stringify.value(evaluated.simulation, .{ .whitespace = .indent_2 }, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    } else {
        var buffer: [4096]u8 = undefined;
        var writer = std.Io.File.stdout().writer(init.io, &buffer);
        try std.json.Stringify.value(evaluated.simulation, .{ .whitespace = .indent_2 }, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    var replay_file = try std.Io.Dir.cwd().createFile(init.io, replay_file_path, .{});
    defer replay_file.close(init.io);
    var replay_buffer: [8192]u8 = undefined;
    var replay_writer = replay_file.writer(init.io, &replay_buffer);
    for (evaluated.replay_events) |*event| {
        try std.json.Stringify.value(event.view(), .{}, &replay_writer.interface);
        try replay_writer.interface.writeByte('\n');
    }
    try replay_writer.interface.flush();
    return 0;
}

fn runHosted(init: std.process.Init, allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    if (args.len != 10) return error.InvalidArguments;
    var mission_path: ?[]const u8 = null;
    var hidden_path: ?[]const u8 = null;
    var submission_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var index: usize = 2;
    while (index < args.len) : (index += 2) {
        const flag = args[index];
        const value = args[index + 1];
        if (std.mem.eql(u8, flag, "--mission")) try setOnce(&mission_path, value) else if (std.mem.eql(u8, flag, "--hidden-season")) try setOnce(&hidden_path, value) else if (std.mem.eql(u8, flag, "--submission")) try setOnce(&submission_path, value) else if (std.mem.eql(u8, flag, "--output-dir")) try setOnce(&output_path, value) else return error.InvalidArguments;
    }

    const mission_json = try readFileAll(allocator, init.io, mission_path orelse return error.InvalidArguments);
    const hidden_json = try readFileAll(allocator, init.io, hidden_path orelse return error.InvalidArguments);
    const submission_json = try readFileAll(allocator, init.io, submission_path orelse return error.InvalidArguments);
    const artifacts = try lib.hosted_evaluator.evaluateHosted(allocator, mission_json, hidden_json, submission_json);

    var output_dir = try std.Io.Dir.cwd().createDirPathOpen(init.io, output_path orelse return error.InvalidArguments, .{});
    defer output_dir.close(init.io);
    try writeAtomic(init.io, output_dir, "result.json", artifacts.result_json);
    try writeAtomic(init.io, output_dir, "scorecard.json", artifacts.scorecard_json);
    try writeAtomic(init.io, output_dir, "replay.jsonl", artifacts.replay_jsonl);
    return 0;
}

fn packHidden(init: std.process.Init, allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    if (args.len != 12) return error.InvalidArguments;
    var mission_path: ?[]const u8 = null;
    var environment_path: ?[]const u8 = null;
    var config_path: ?[]const u8 = null;
    var seed_text: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var index: usize = 2;
    while (index < args.len) : (index += 2) {
        const flag = args[index];
        const value = args[index + 1];
        if (std.mem.eql(u8, flag, "--mission")) try setOnce(&mission_path, value) else if (std.mem.eql(u8, flag, "--environment")) try setOnce(&environment_path, value) else if (std.mem.eql(u8, flag, "--backend-config")) try setOnce(&config_path, value) else if (std.mem.eql(u8, flag, "--seed")) try setOnce(&seed_text, value) else if (std.mem.eql(u8, flag, "--output")) try setOnce(&output_path, value) else return error.InvalidArguments;
    }
    const mission_json = try readFileAll(allocator, init.io, mission_path orelse return error.InvalidArguments);
    const environment_json = try readFileAll(allocator, init.io, environment_path orelse return error.InvalidArguments);
    const config_json = try readFileAll(allocator, init.io, config_path orelse return error.InvalidArguments);
    const seed = try std.fmt.parseInt(u64, seed_text orelse return error.InvalidArguments, 10);
    const hidden_json = try lib.hosted_evaluator.packHiddenSeason(allocator, mission_json, environment_json, config_json, seed);
    try writePath(init.io, output_path orelse return error.InvalidArguments, hidden_json);
    return 0;
}

fn setOnce(slot: *?[]const u8, value: []const u8) !void {
    if (slot.* != null or value.len == 0) return error.InvalidArguments;
    slot.* = value;
}

fn writePath(io: std.Io, path: []const u8, bytes: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var buffer: [8192]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

fn writeAtomic(io: std.Io, dir: std.Io.Dir, name: []const u8, bytes: []const u8) !void {
    var temporary_name_buffer: [128]u8 = undefined;
    const temporary_name = try std.fmt.bufPrint(&temporary_name_buffer, ".{s}.tmp", .{name});
    {
        var file = try dir.createFile(io, temporary_name, .{});
        defer file.close(io);
        var buffer: [8192]u8 = undefined;
        var writer = file.writer(io, &buffer);
        try writer.interface.writeAll(bytes);
        try writer.interface.flush();
    }
    try dir.rename(temporary_name, dir, name, io);
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

fn compositeEnvironmentSha(environment: []const u8, config: []const u8) [64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("yard-mercury/environment/v0\x00");
    hasher.update(environment);
    hasher.update("\x00");
    hasher.update(config);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}
