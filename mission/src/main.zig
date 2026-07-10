//! yard-mission CLI.
//!
//! Usage:
//!   yard-mission eval <mission.json> <submission.json> [--results <file.jsonl>] [--append]
//!
//! Prints a canonical JSON report to stdout. With --results, the submission is
//! placed against the leaderboard; with --append, a scored entry is appended.

const std = @import("std");
const mission_lib = @import("yard_mission");

pub fn main(init: std.process.Init) !u8 {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args_buf: std.ArrayList([]const u8) = .empty;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    while (it.next()) |a| try args_buf.append(allocator, a);
    const args = args_buf.items;

    if (args.len < 4 or !std.mem.eql(u8, args[1], "eval")) {
        std.log.err("usage: yard-mission eval <mission.json> <submission.json> [--results <file.jsonl>] [--append]", .{});
        return 1;
    }

    var results_path: ?[]const u8 = null;
    var append = false;
    var i: usize = 4;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--results") and i + 1 < args.len) {
            results_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--append")) {
            append = true;
        }
    }

    const mission_json = readFileAll(allocator, init.io, args[2]) catch |err| {
        std.log.err("cannot read mission {s}: {s}", .{ args[2], @errorName(err) });
        return 1;
    };
    const submission_json = readFileAll(allocator, init.io, args[3]) catch |err| {
        std.log.err("cannot read submission {s}: {s}", .{ args[3], @errorName(err) });
        return 1;
    };

    const mission = mission_lib.spec.parseMission(allocator, mission_json) catch |err| {
        std.log.err("mission parse failed: {s}", .{@errorName(err)});
        return 1;
    };
    const submission = mission_lib.spec.parseSubmission(allocator, submission_json) catch |err| {
        std.log.err("submission parse failed: {s}", .{@errorName(err)});
        return 1;
    };

    var leaderboard: []const []const f64 = &.{};
    if (results_path) |path| {
        if (readFileAll(allocator, init.io, path)) |text| {
            leaderboard = try mission_lib.runner.parseLeaderboard(
                allocator,
                text,
                mission.value.id,
                mission.value.objectives.len,
            );
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => {
                std.log.err("cannot read results {s}: {s}", .{ path, @errorName(err) });
                return 1;
            },
        }
    }

    const report = mission_lib.runner.evaluate(allocator, mission.value, submission.value, leaderboard) catch |err| {
        std.log.err("evaluation failed: {s}", .{@errorName(err)});
        return 1;
    };

    var out: std.ArrayList(u8) = .empty;
    try mission_lib.runner.renderReportJson(&out, allocator, report, mission.value.objectives);

    var stdout_buf: [8192]u8 = undefined;
    var stdout_w = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const w = &stdout_w.interface;
    try w.writeAll(out.items);
    try w.flush();

    if (append and report.scored) {
        if (results_path) |path| {
            var contents: std.ArrayList(u8) = .empty;
            const existing = readFileAll(allocator, init.io, path) catch |err| switch (err) {
                error.FileNotFound => "",
                else => return err,
            };
            try contents.appendSlice(allocator, existing);
            try mission_lib.runner.renderEntryLine(&contents, allocator, report);
            var f = try std.Io.Dir.cwd().createFile(init.io, path, .{});
            defer f.close(init.io);
            try f.writePositionalAll(init.io, contents.items, 0);
            std.log.info("appended entry to {s}", .{path});
        }
    }

    return if (report.scored) 0 else 2;
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
