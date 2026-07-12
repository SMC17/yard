const inner = @import("src/root.zig");

pub const types = inner.types;
pub const policy = inner.policy;
pub const simulation = inner.simulation;
pub const arena = inner.arena;

test {
    _ = inner;
}
