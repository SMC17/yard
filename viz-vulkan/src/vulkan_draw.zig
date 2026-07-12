//! Native Vulkan frame bootstrap: device probe, GPU clear/readback, 3D overlay.

const std = @import("std");
const frame = @import("frame.zig");
const native = @import("vulkan_native.zig");
const scene = @import("scene.zig");

pub const Error = error{
    VulkanCallFailed,
    NoDevice,
    NoQueue,
    NoHostVisibleMemory,
    InvalidFrameSize,
    InvalidRgbaBuffer,
    OutOfMemory,
};

pub const Device = struct {
    context: native.Context,

    pub fn init() Error!Device {
        return .{ .context = native.Context.init() catch |err| return mapNativeError(err) };
    }

    pub fn deinit(self: *Device) void {
        self.context.deinit();
    }

    pub fn probe(self: *const Device) native.Probe {
        return self.context.probe();
    }

    /// Vulkan fills and synchronizes the RGBA frame. The deterministic 3D
    /// wireframe is then composited by the shared reference rasterizer.
    pub fn drawFleetFramePpm(
        self: *const Device,
        allocator: std.mem.Allocator,
        value: scene.Scene,
        width: u32,
        height: u32,
    ) Error![]u8 {
        const rgba = self.context.clearFrameRgba(
            allocator,
            width,
            height,
            frame.background_rgba,
        ) catch |err| return mapNativeError(err);
        defer allocator.free(rgba);
        return frame.renderPpmOnRgba(allocator, value, rgba, width, height) catch |err| switch (err) {
            error.InvalidFrameSize => error.InvalidFrameSize,
            error.InvalidRgbaBuffer => error.InvalidRgbaBuffer,
            error.OutOfMemory => error.OutOfMemory,
        };
    }
};

fn mapNativeError(err: native.Error) Error {
    return switch (err) {
        error.VulkanCallFailed => error.VulkanCallFailed,
        error.NoDevice => error.NoDevice,
        error.NoQueue => error.NoQueue,
        error.NoHostVisibleMemory => error.NoHostVisibleMemory,
        error.InvalidFrameSize => error.InvalidFrameSize,
        error.OutOfMemory => error.OutOfMemory,
    };
}

test "native Vulkan frame matches deterministic reference" {
    if (!@import("build_options").vulkan_enabled) return;
    const json =
        \\{"title":"Native Formation","vessels":[
        \\ {"id":"lead","hull":{"kind":"wigley","length_m":80,"beam_m":12,"draft_m":4},"pose":{"north_m":30,"yaw_rad":0.2,"roll_rad":0.08}},
        \\ {"id":"wing","hull":{"kind":"box_barge","length_m":40,"beam_m":8,"draft_m":3},"pose":{"north_m":-30,"east_m":45,"yaw_rad":-0.25}}
        \\]}
    ;
    const parsed = try scene.parseSceneJson(std.testing.allocator, json);
    defer scene.freeScene(std.testing.allocator, parsed);
    var device = try Device.init();
    defer device.deinit();
    try std.testing.expect(device.probe().device_name.len > 0);

    const gpu_frame = try device.drawFleetFramePpm(std.testing.allocator, parsed, 320, 180);
    defer std.testing.allocator.free(gpu_frame);
    const reference = try frame.renderReferencePpm(std.testing.allocator, parsed, 320, 180);
    defer std.testing.allocator.free(reference);
    try std.testing.expectEqualSlices(u8, reference, gpu_frame);
}
