//! yard-viz — deterministic visualization primitives for yard workflows.
//!
//! Phase 1: SVG curve export (GZ, resistance curves).
//! Phase 2: Vulkan 3D hull + overlay rendering (see viz-vulkan/).

pub const gz_svg = @import("gz_svg.zig");
pub const pareto_svg = @import("pareto_svg.zig");
pub const hull_profile_svg = @import("hull_profile_svg.zig");

test {
    _ = gz_svg;
    _ = pareto_svg;
    _ = hull_profile_svg;
}