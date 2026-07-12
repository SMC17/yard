//! yard-viz-vulkan — fleet scene graph, reference frames, and Vulkan bootstrap.

pub const scene = @import("scene.zig");
pub const headless = @import("headless.zig");
pub const frame = @import("frame.zig");

pub const vulkan_enabled = @import("build_options").vulkan_enabled;
pub const vulkan_draw = if (vulkan_enabled) @import("vulkan_draw.zig") else struct {};

test {
    _ = scene;
    _ = headless;
    _ = frame;
    _ = vulkan_draw;
}
