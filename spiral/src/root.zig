//! yard-spiral — Evans 1959 Ship Design Spiral orchestrator.
//!
//! Multi-fidelity iterative design loops wiring yard primitives into an
//! auditable digital design spiral with similarity-native model testing.

pub const stages = @import("stages.zig");
pub const orchestrator = @import("orchestrator.zig");
pub const optimizer = @import("optimizer.zig");
pub const codegen = @import("codegen.zig");

test {
    _ = stages;
    _ = orchestrator;
    _ = optimizer;
    _ = codegen;
}