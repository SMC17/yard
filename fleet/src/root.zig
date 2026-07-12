//! Yard generic multi-vessel design and hierarchical formation package.

pub const design = @import("design.zig");
pub const scantlings = @import("scantlings.zig");
pub const compiler = @import("compiler.zig");
pub const formation = @import("formation.zig");

test {
    _ = design;
    _ = scantlings;
    _ = compiler;
    _ = formation;
}
