//! yard-compose — multi-module naval architecture workflows.
//!
//! Proof level: unit-tested (inherits hydro + stability primitives).

pub const box_barge = @import("box_barge.zig");
pub const cargo_resistance = @import("cargo_resistance.zig");
pub const vessel_assessment = @import("vessel_assessment.zig");
pub const seakeeping_assessment = @import("seakeeping_assessment.zig");
pub const damage_stability = @import("damage_stability.zig");
pub const time_domain_sim = @import("time_domain_sim.zig");
pub const irregular_wave_sim = @import("irregular_wave_sim.zig");
pub const dp_station_keeping = @import("dp_station_keeping.zig");
pub const coupled_dp_waves = @import("coupled_dp_waves.zig");
pub const pareto_report = @import("pareto_report.zig");
pub const design_spiral = @import("design_spiral.zig");
pub const regulatory_assessment = @import("regulatory_assessment.zig");

test {
    _ = box_barge;
    _ = cargo_resistance;
    _ = vessel_assessment;
    _ = seakeeping_assessment;
    _ = damage_stability;
    _ = time_domain_sim;
    _ = irregular_wave_sim;
    _ = dp_station_keeping;
    _ = coupled_dp_waves;
    _ = pareto_report;
    _ = design_spiral;
    _ = regulatory_assessment;
}