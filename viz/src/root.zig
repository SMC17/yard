//! yard-viz — deterministic visualization primitives for yard workflows.
//!
//! Phase 1: SVG curve export (GZ, resistance curves).
//! Phase 2: Vulkan 3D hull + overlay rendering (see viz-vulkan/).

pub const gz_svg = @import("gz_svg.zig");

test {
    _ = gz_svg;
}