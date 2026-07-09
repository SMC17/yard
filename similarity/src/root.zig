//! yard-similarity — geometric, kinematic, and dynamic similarity laws.
//!
//! Implements the three fundamental rules of model testing (Evans spiral /
//! ITTC practice): geometric scaling of dimensions, kinematic scaling of
//! velocities (Froude for gravity-wave effects), and dynamic scaling checks
//! (Reynolds for viscous effects).

pub const scale = @import("scale.zig");
pub const froude = @import("froude.zig");
pub const reynolds = @import("reynolds.zig");
pub const extrapolation = @import("extrapolation.zig");

test {
    _ = scale;
    _ = froude;
    _ = reynolds;
    _ = extrapolation;
}