//! Emit a Yard Arena RNG conformance vector.
//! Usage: zig build rng-vector -- <seed-u64> <stream-u8> <draw-index-u64>

const std = @import("std");
const yard_arena = @import("yard_arena");
const rng = yard_arena.counter_rng;

pub fn main(init: std.process.Init) !u8 {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args: std.ArrayList([]const u8) = .empty;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    while (it.next()) |arg| try args.append(allocator, arg);
    if (args.items.len != 4) return 1;

    const seed = std.fmt.parseInt(u64, args.items[1], 0) catch return 1;
    const stream_id = std.fmt.parseInt(u8, args.items[2], 0) catch return 1;
    const draw_index = std.fmt.parseInt(u64, args.items[3], 0) catch return 1;
    const value = rng.drawU64(seed, stream_id, draw_index);

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "{{\"algorithm\":\"{s}\",\"seed\":\"{d}\",\"stream_id\":{d},\"draw_index\":\"{d}\",\"u64_hex\":\"{x:0>16}\",\"unit_f64\":{d:.17}}}\n",
        .{ rng.algorithm_id, seed, stream_id, draw_index, value, rng.drawUnitF64(seed, stream_id, draw_index) },
    );
    try stdout.flush();
    return 0;
}
