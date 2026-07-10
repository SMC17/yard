//! yard-sailaero — sail aerodynamics: apparent wind, ORC VPP 2023 rig
//! coefficients, a braced square-rig model, and steady-state speed polars.
//!
//! Serves the Age-of-Sail Trials missions and the interactive sailing demo
//! from one force model. Hull resistance stays abstract (caller-supplied
//! table), so any yard hull module can sit underneath.
//!
//! Proof level: unit-tested. Fore-and-aft coefficients transcribed from ORC
//! VPP Documentation 2023 (Tables 5.1, 5.4); square rig is a documented
//! flat-plate approximation pending clipper passage-data validation.

pub const apparent = @import("apparent.zig");
pub const coeffs = @import("coeffs.zig");
pub const rig = @import("rig.zig");
pub const squarerig = @import("squarerig.zig");
pub const polar = @import("polar.zig");

test {
    _ = apparent;
    _ = coeffs;
    _ = rig;
    _ = squarerig;
    _ = polar;
}
