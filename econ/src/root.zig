//! yard-econ — voyage economics for the Yard Trials.
//!
//! Standard maritime-economics formulation: capital recovery amortization,
//! operating costs with an expected-loss insurance premium taken straight
//! from the mission Monte Carlo loss rate, per-voyage costs, and Required
//! Freight Rate. Inputs are plain numbers so any voyage model (mission
//! runner, sail polar integration, historical scenario) can sit upstream.
//!
//! Proof level: unit-tested (closed-form finance math, exact).

pub const model = @import("model.zig");

test {
    _ = model;
}
