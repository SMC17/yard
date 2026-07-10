//! yard-mission — mission spec + eval runner for the Yard Trials.
//!
//! A mission is a constraint envelope, an environment, and an objective set.
//! Submissions are parametric vessels. Evaluation chains validity gates
//! (intact stability, freeboard, era envelope, model validity) into a seeded
//! Monte Carlo voyage simulation and places the objective vector on the
//! mission's Pareto frontier.
//!
//! Proof level: unit-tested (inherits hydro + stability + resistance primitives).

pub const spec = @import("spec.zig");
pub const gates = @import("gates.zig");
pub const voyage = @import("voyage.zig");
pub const pareto = @import("pareto.zig");
pub const runner = @import("runner.zig");

test {
    _ = spec;
    _ = gates;
    _ = voyage;
    _ = pareto;
    _ = runner;
}
