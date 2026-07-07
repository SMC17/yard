//! yard-compose — multi-module naval architecture workflows.
//!
//! Proof level: unit-tested (inherits hydro + stability primitives).

pub const box_barge = @import("box_barge.zig");

test {
    _ = box_barge;
}