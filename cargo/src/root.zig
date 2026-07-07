// yard-cargo-zig public API.
//
// container:  ISO 668 container TEU / FEU geometry, tare and gross
//             mass classes, stacking weight, max gross at corner
//             posts (CSC plate).
//
// breakbulk:  Breakbulk stowage factor (m^3 / tonne) per cargo
//             class; broken-stowage allowance; load-density per
//             hold.
//
// project:    Project cargo / heavy lift: skid-mount load, jacking
//             schedule for blocking/cribbing, sling angle and SWL
//             check.

pub const container = @import("container.zig");
pub const breakbulk = @import("breakbulk.zig");
pub const project = @import("project.zig");

test {
    _ = container;
    _ = breakbulk;
    _ = project;
}
