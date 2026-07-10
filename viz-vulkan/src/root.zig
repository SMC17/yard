//! yard-viz-vulkan — scene graph + headless SVG bridge.
//! Full Vulkan draw path: enable with `-Dvulkan=enabled` (Phase 2b).

pub const scene = @import("scene.zig");
pub const headless = @import("headless.zig");

pub const vulkan_enabled = @import("build_options").vulkan_enabled;

test {
    _ = scene;
    _ = headless;
    if (vulkan_enabled) {
        _ = @import("vulkan_draw.zig");
    }
}