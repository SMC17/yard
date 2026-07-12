//! Yard Arena's versioned, stream-separated counter RNG primitive.

const std = @import("std");

pub const algorithm_id = "blake3-counter-v1";
const domain = "yard-arena/blake3-counter-v1";

/// `stream_id` is fixed by the consuming protocol. `draw_index` is a
/// random-access coordinate, not mutable RNG state.
pub fn drawU64(seed: u64, stream_id: u8, draw_index: u64) u64 {
    var input: [domain.len + 1 + 8 + 1 + 8]u8 = undefined;
    @memcpy(input[0..domain.len], domain);
    input[domain.len] = 0;
    std.mem.writeInt(u64, input[domain.len + 1 ..][0..8], seed, .little);
    input[domain.len + 9] = stream_id;
    std.mem.writeInt(u64, input[domain.len + 10 ..][0..8], draw_index, .little);

    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(&input, &digest, .{});
    return std.mem.readInt(u64, digest[0..8], .little);
}

pub fn drawUnitF64(seed: u64, stream_id: u8, draw_index: u64) f64 {
    const mantissa = drawU64(seed, stream_id, draw_index) >> 11;
    return @as(f64, @floatFromInt(mantissa)) * (1.0 / 9007199254740992.0);
}

test "raw counter draws are coordinate-stable" {
    try std.testing.expectEqual(drawU64(42, 3, 7), drawU64(42, 3, 7));
    try std.testing.expect(drawU64(42, 3, 7) != drawU64(42, 4, 7));
}

test "published blake3-counter-v1 conformance vector" {
    try std.testing.expectEqual(@as(u64, 0x99bc0b490101ad93), drawU64(42, 0, 7));
}
