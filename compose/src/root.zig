//! yard-compose — multi-module naval architecture workflows.
//!
//! Proof level: unit-tested (inherits hydro + stability primitives).

pub const box_barge = @import("box_barge.zig");
pub const cargo_resistance = @import("cargo_resistance.zig");
pub const vessel_assessment = @import("vessel_assessment.zig");

test {
    _ = box_barge;
    _ = cargo_resistance;
    _ = vessel_assessment;
}