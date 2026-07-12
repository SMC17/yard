//! Commit, sign, and verify exact hidden-season manifest bytes.

const std = @import("std");
const arena = @import("yard_arena");

const WireEnvelope = struct {
    algorithm: []const u8,
    key_id: []const u8,
    payload_sha256: []const u8,
    public_key_hex: []const u8,
    signature_hex: []const u8,
};

pub fn main(init: std.process.Init) !u8 {
    return run(init) catch |err| {
        var buffer: [1024]u8 = undefined;
        var writer = std.Io.File.stderr().writer(init.io, &buffer);
        try writer.interface.print("yard-arena-season: {s}\n", .{@errorName(err)});
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
    const args = arguments.items;
    if (args.len < 3) return error.InvalidArguments;
    const payload = try readFileAll(allocator, init.io, args[2]);

    if (std.mem.eql(u8, args[1], "commit") and args.len == 3) {
        const commitment = arena.season.payloadCommitment(payload);
        return writeStatus(init, &commitment, null, true);
    }
    if (std.mem.eql(u8, args[1], "sign") and args.len == 6) {
        const seed_text = std.mem.trim(u8, try readFileAll(allocator, init.io, args[3]), " \t\r\n");
        var seed: [std.crypto.sign.Ed25519.KeyPair.seed_length]u8 = undefined;
        if (seed_text.len != seed.len * 2) return error.InvalidSeed;
        _ = try std.fmt.hexToBytes(&seed, seed_text);
        const envelope = try arena.season.sign(payload, args[4], seed);
        var file = try std.Io.Dir.cwd().createFile(init.io, args[5], .{});
        defer file.close(init.io);
        var buffer: [4096]u8 = undefined;
        var writer = file.writer(init.io, &buffer);
        const wire: WireEnvelope = .{
            .algorithm = envelope.algorithm,
            .key_id = envelope.key_id,
            .payload_sha256 = &envelope.payload_sha256,
            .public_key_hex = &envelope.public_key_hex,
            .signature_hex = &envelope.signature_hex,
        };
        try std.json.Stringify.value(wire, .{ .whitespace = .indent_2 }, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
        return writeStatus(init, &envelope.payload_sha256, envelope.key_id, true);
    }
    if (std.mem.eql(u8, args[1], "verify") and args.len == 6) {
        const envelope_bytes = try readFileAll(allocator, init.io, args[3]);
        const wire = try std.json.parseFromSlice(WireEnvelope, allocator, envelope_bytes, .{});
        var envelope: arena.season.SignatureEnvelope = .{
            .algorithm = wire.value.algorithm,
            .key_id = wire.value.key_id,
            .payload_sha256 = undefined,
            .public_key_hex = undefined,
            .signature_hex = undefined,
        };
        if (wire.value.payload_sha256.len != envelope.payload_sha256.len or
            wire.value.public_key_hex.len != envelope.public_key_hex.len or
            wire.value.signature_hex.len != envelope.signature_hex.len) return error.InvalidEnvelope;
        @memcpy(&envelope.payload_sha256, wire.value.payload_sha256);
        @memcpy(&envelope.public_key_hex, wire.value.public_key_hex);
        @memcpy(&envelope.signature_hex, wire.value.signature_hex);
        const expected_key_id = args[4];
        const expected_public_key = args[5];
        const trusted = std.mem.eql(u8, envelope.key_id, expected_key_id) and
            std.mem.eql(u8, &envelope.public_key_hex, expected_public_key);
        const valid = trusted and arena.season.verify(payload, envelope);
        _ = try writeStatus(init, &envelope.payload_sha256, envelope.key_id, valid);
        return if (valid) 0 else 2;
    }
    return error.InvalidArguments;
}

fn writeStatus(init: std.process.Init, commitment: []const u8, key_id: ?[]const u8, valid: bool) !u8 {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    if (key_id) |key| {
        try writer.interface.print(
            "{{\"valid\":{},\"algorithm\":\"{s}\",\"key_id\":\"{s}\",\"payload_sha256\":\"{s}\"}}\n",
            .{ valid, arena.season.signature_algorithm, key, commitment },
        );
    } else {
        try writer.interface.print("{{\"valid\":{},\"payload_sha256\":\"{s}\"}}\n", .{ valid, commitment });
    }
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
