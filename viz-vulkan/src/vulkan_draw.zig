//! Vulkan draw stub — Phase 2b. Requires `-Dvulkan=enabled` and system Vulkan SDK.

const std = @import("std");

pub const Error = error{
    VulkanNotLinked,
};

pub fn initDevice() Error!void {
    return Error.VulkanNotLinked;
}

pub fn drawHullLineStrip(_: []const f32) Error!void {
    return Error.VulkanNotLinked;
}

test "vulkan stub compiles when enabled" {
    try std.testing.expectError(Error.VulkanNotLinked, initDevice());
}