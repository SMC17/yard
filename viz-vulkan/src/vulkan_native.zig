//! Native Vulkan context and deterministic command-buffer readback.

const builtin = @import("builtin");
const std = @import("std");
const vk = @import("vulkan_types.zig");

pub const Error = error{
    VulkanCallFailed,
    NoDevice,
    NoQueue,
    NoHostVisibleMemory,
    InvalidFrameSize,
    OutOfMemory,
};

pub const Probe = struct {
    device_name: []const u8,
    api_version: u32,
    vendor_id: u32,
    device_id: u32,
    device_type: u32,
    queue_family_index: u32,
};

pub const Context = struct {
    instance: vk.Instance,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    queue: vk.Queue,
    queue_family_index: u32,
    memory_properties: vk.PhysicalDeviceMemoryProperties,
    properties: vk.PhysicalDeviceProperties,

    pub fn init() Error!Context {
        var instance: vk.Instance = null;
        const app: vk.ApplicationInfo = .{
            .application_name = "yard-viz-vulkan",
            .engine_name = "yard",
        };
        try check(vk.vkCreateInstance(&.{ .application_info = &app }, null, &instance));
        errdefer vk.vkDestroyInstance(instance, null);

        var device_count: u32 = 0;
        try check(vk.vkEnumeratePhysicalDevices(instance, &device_count, null));
        if (device_count == 0) return error.NoDevice;
        var physical_devices: [16]vk.PhysicalDevice = @splat(null);
        if (device_count > physical_devices.len) device_count = physical_devices.len;
        try check(vk.vkEnumeratePhysicalDevices(instance, &device_count, &physical_devices));

        var selected_device: vk.PhysicalDevice = null;
        var selected_family: ?u32 = null;
        for (physical_devices[0..device_count]) |candidate| {
            const family = findQueueFamily(candidate) catch continue;
            selected_device = candidate;
            selected_family = family;
            break;
        }
        const queue_family_index = selected_family orelse return error.NoQueue;

        const priority: f32 = 1.0;
        const queue_info: vk.DeviceQueueCreateInfo = .{
            .queue_family_index = queue_family_index,
            .queue_priorities = @ptrCast(&priority),
        };
        var device: vk.Device = null;
        try check(vk.vkCreateDevice(
            selected_device,
            &.{ .queue_create_infos = &queue_info },
            null,
            &device,
        ));
        errdefer vk.vkDestroyDevice(device, null);

        var queue: vk.Queue = null;
        vk.vkGetDeviceQueue(device, queue_family_index, 0, &queue);
        if (queue == null) return error.NoQueue;

        var memory_properties: vk.PhysicalDeviceMemoryProperties = undefined;
        vk.vkGetPhysicalDeviceMemoryProperties(selected_device, &memory_properties);
        var properties: vk.PhysicalDeviceProperties = undefined;
        vk.vkGetPhysicalDeviceProperties(selected_device, &properties);

        return .{
            .instance = instance,
            .physical_device = selected_device,
            .device = device,
            .queue = queue,
            .queue_family_index = queue_family_index,
            .memory_properties = memory_properties,
            .properties = properties,
        };
    }

    pub fn deinit(self: *Context) void {
        if (self.device != null) {
            _ = vk.vkDeviceWaitIdle(self.device);
            vk.vkDestroyDevice(self.device, null);
        }
        if (self.instance != null) vk.vkDestroyInstance(self.instance, null);
        self.* = undefined;
    }

    pub fn probe(self: *const Context) Probe {
        var end: usize = 0;
        while (end < self.properties.device_name.len and self.properties.device_name[end] != 0) : (end += 1) {}
        return .{
            .device_name = self.properties.device_name[0..end],
            .api_version = self.properties.api_version,
            .vendor_id = self.properties.vendor_id,
            .device_id = self.properties.device_id,
            .device_type = self.properties.device_type,
            .queue_family_index = self.queue_family_index,
        };
    }

    /// Creates a host-visible RGBA buffer, fills it through a Vulkan command
    /// buffer, waits for completion, and returns a CPU-owned readback.
    pub fn clearFrameRgba(
        self: *const Context,
        allocator: std.mem.Allocator,
        width: u32,
        height: u32,
        rgba: [4]u8,
    ) Error![]u8 {
        if (width == 0 or height == 0) return error.InvalidFrameSize;
        const pixel_count = std.math.mul(usize, width, height) catch return error.InvalidFrameSize;
        const byte_count = std.math.mul(usize, pixel_count, 4) catch return error.InvalidFrameSize;

        var buffer: vk.NonDispatchable = 0;
        try check(vk.vkCreateBuffer(self.device, &.{
            .size = byte_count,
            .usage = vk.BUFFER_USAGE_TRANSFER_DST_BIT,
        }, null, &buffer));
        defer vk.vkDestroyBuffer(self.device, buffer, null);

        var requirements: vk.MemoryRequirements = undefined;
        vk.vkGetBufferMemoryRequirements(self.device, buffer, &requirements);
        const memory_type_index = try findMemoryType(
            &self.memory_properties,
            requirements.memory_type_bits,
            vk.MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.MEMORY_PROPERTY_HOST_COHERENT_BIT,
        );

        var memory: vk.NonDispatchable = 0;
        try check(vk.vkAllocateMemory(self.device, &.{
            .allocation_size = requirements.size,
            .memory_type_index = memory_type_index,
        }, null, &memory));
        defer vk.vkFreeMemory(self.device, memory, null);
        try check(vk.vkBindBufferMemory(self.device, buffer, memory, 0));

        var command_pool: vk.NonDispatchable = 0;
        try check(vk.vkCreateCommandPool(self.device, &.{
            .queue_family_index = self.queue_family_index,
        }, null, &command_pool));
        defer vk.vkDestroyCommandPool(self.device, command_pool, null);

        var command_buffer: vk.CommandBuffer = null;
        try check(vk.vkAllocateCommandBuffers(self.device, &.{
            .command_pool = command_pool,
        }, &command_buffer));
        try check(vk.vkBeginCommandBuffer(command_buffer, &.{}));
        vk.vkCmdFillBuffer(command_buffer, buffer, 0, byte_count, rgbaWord(rgba));
        try check(vk.vkEndCommandBuffer(command_buffer));

        const submit: vk.SubmitInfo = .{
            .command_buffers = @ptrCast(&command_buffer),
        };
        try check(vk.vkQueueSubmit(self.queue, 1, @ptrCast(&submit), 0));
        try check(vk.vkQueueWaitIdle(self.queue));

        var mapped: ?*anyopaque = null;
        try check(vk.vkMapMemory(self.device, memory, 0, byte_count, 0, &mapped));
        defer vk.vkUnmapMemory(self.device, memory);
        const source: [*]const u8 = @ptrCast(mapped orelse return error.VulkanCallFailed);
        return allocator.dupe(u8, source[0..byte_count]) catch error.OutOfMemory;
    }
};

fn check(result: vk.Result) Error!void {
    if (result != vk.SUCCESS) return error.VulkanCallFailed;
}

fn findQueueFamily(device: vk.PhysicalDevice) Error!u32 {
    var count: u32 = 0;
    vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &count, null);
    if (count == 0) return error.NoQueue;
    var properties: [32]vk.QueueFamilyProperties = undefined;
    if (count > properties.len) count = properties.len;
    vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &count, &properties);

    for (properties[0..count], 0..) |property, index| {
        if (property.queue_count > 0 and property.queue_flags & vk.QUEUE_GRAPHICS_BIT != 0)
            return @intCast(index);
    }
    for (properties[0..count], 0..) |property, index| {
        const useful = vk.QUEUE_COMPUTE_BIT | vk.QUEUE_TRANSFER_BIT;
        if (property.queue_count > 0 and property.queue_flags & useful != 0)
            return @intCast(index);
    }
    return error.NoQueue;
}

fn findMemoryType(
    properties: *const vk.PhysicalDeviceMemoryProperties,
    type_bits: u32,
    required_flags: u32,
) Error!u32 {
    for (0..properties.memory_type_count) |index| {
        const bit = @as(u32, 1) << @intCast(index);
        if (type_bits & bit != 0 and
            properties.memory_types[index].property_flags & required_flags == required_flags)
        {
            return @intCast(index);
        }
    }
    return error.NoHostVisibleMemory;
}

fn rgbaWord(rgba: [4]u8) u32 {
    return switch (builtin.cpu.arch.endian()) {
        .little => @as(u32, rgba[0]) |
            (@as(u32, rgba[1]) << 8) |
            (@as(u32, rgba[2]) << 16) |
            (@as(u32, rgba[3]) << 24),
        .big => (@as(u32, rgba[0]) << 24) |
            (@as(u32, rgba[1]) << 16) |
            (@as(u32, rgba[2]) << 8) |
            @as(u32, rgba[3]),
    };
}

test "RGBA word preserves byte order" {
    var word = rgbaWord(.{ 0x12, 0x1c, 0x28, 0xff });
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0x1c, 0x28, 0xff }, std.mem.asBytes(&word));
}
