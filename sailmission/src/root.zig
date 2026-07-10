//! yard-sailmission — Age-of-Sail Trials missions: era-gated, sail-physics
//! Monte Carlo passages with Pareto scoring.
//!
//! Composes sailaero (ORC rig + square-rig polars, leeway drag), era
//! (constraint envelopes), the canonical box-barge stability workflow, and
//! ITTC-57 friction resistance. Self-contained module; consolidates into
//! mission/ once the in-flight fleet work there lands.
//!
//! Proof level: unit-tested; the m1 fixture is validated in aggregate
//! against the historical Shanghai->London passage band (pre-registered).

pub const spec = @import("spec.zig");
pub const fixtures = @import("fixtures.zig");
pub const physics = @import("physics.zig");
pub const gates = @import("gates.zig");
pub const voyage = @import("voyage.zig");
pub const runner = @import("runner.zig");

test {
    _ = spec;
    _ = fixtures;
    _ = physics;
    _ = gates;
    _ = voyage;
    _ = runner;
}
