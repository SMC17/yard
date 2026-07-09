//! yard-compose — multi-module naval architecture workflows.
//!
//! Proof level: unit-tested (inherits hydro + stability primitives).

pub const box_barge = @import("box_barge.zig");
pub const cargo_resistance = @import("cargo_resistance.zig");
pub const vessel_assessment = @import("vessel_assessment.zig");
pub const seakeeping_assessment = @import("seakeeping_assessment.zig");
pub const damage_stability = @import("damage_stability.zig");
pub const time_domain_sim = @import("time_domain_sim.zig");
pub const design_spiral = @import("design_spiral.zig");

test {
    _ = box_barge;
    _ = cargo_resistance;
    _ = vessel_assessment;
    _ = seakeeping_assessment;
    _ = damage_stability;
    _ = time_domain_sim;
    _ = design_spiral;
}