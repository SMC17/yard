//! Stable, stream-separated counter RNG for competition backends.

const std = @import("std");
const types = @import("types.zig");
const counter_rng = @import("counter_rng.zig");

pub const algorithm_id = counter_rng.algorithm_id;

/// Returns a random-access draw. Adding draws to one stream cannot perturb any
/// other stream because the stream and draw index are part of the hash input.
pub fn drawU64(seed: u64, stream: types.RngStream, draw_index: u64) u64 {
    return counter_rng.drawU64(seed, @intFromEnum(stream), draw_index);
}

pub fn drawUnitF64(seed: u64, stream: types.RngStream, draw_index: u64) f64 {
    return counter_rng.drawUnitF64(seed, @intFromEnum(stream), draw_index);
}

test "counter RNG is stable for identical coordinates" {
    const a = drawU64(42, .weather, 7);
    const b = drawU64(42, .weather, 7);
    try std.testing.expectEqual(a, b);
}

test "streams are independent and random-access" {
    const demand_before = drawU64(9, .demand, 3);
    _ = drawU64(9, .weather, 0);
    _ = drawU64(9, .weather, 1);
    _ = drawU64(9, .weather, 2);
    const demand_after = drawU64(9, .demand, 3);
    try std.testing.expectEqual(demand_before, demand_after);
    try std.testing.expect(demand_before != drawU64(9, .weather, 3));
}

test "unit draws stay in half-open interval" {
    for (0..128) |i| {
        const value = drawUnitF64(1234, .traffic, i);
        try std.testing.expect(value >= 0.0);
        try std.testing.expect(value < 1.0);
    }
}
