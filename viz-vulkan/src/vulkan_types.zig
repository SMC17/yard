//! Minimal Vulkan 1.0 ABI used by the headless native frame path.
//! Dispatchable handles are pointers; non-dispatchable handles are 64-bit.

pub const Result = i32;
pub const SUCCESS: Result = 0;

pub const Instance = ?*anyopaque;
pub const PhysicalDevice = ?*anyopaque;
pub const Device = ?*anyopaque;
pub const Queue = ?*anyopaque;
pub const CommandBuffer = ?*anyopaque;
pub const NonDispatchable = u64;

pub const STRUCTURE_TYPE_APPLICATION_INFO: u32 = 0;
pub const STRUCTURE_TYPE_INSTANCE_CREATE_INFO: u32 = 1;
pub const STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO: u32 = 2;
pub const STRUCTURE_TYPE_DEVICE_CREATE_INFO: u32 = 3;
pub const STRUCTURE_TYPE_SUBMIT_INFO: u32 = 4;
pub const STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO: u32 = 5;
pub const STRUCTURE_TYPE_BUFFER_CREATE_INFO: u32 = 12;
pub const STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO: u32 = 39;
pub const STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO: u32 = 40;
pub const STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO: u32 = 42;

pub const API_VERSION_1_0: u32 = 1 << 22;
pub const QUEUE_GRAPHICS_BIT: u32 = 0x1;
pub const QUEUE_COMPUTE_BIT: u32 = 0x2;
pub const QUEUE_TRANSFER_BIT: u32 = 0x4;
pub const BUFFER_USAGE_TRANSFER_DST_BIT: u32 = 0x2;
pub const MEMORY_PROPERTY_HOST_VISIBLE_BIT: u32 = 0x2;
pub const MEMORY_PROPERTY_HOST_COHERENT_BIT: u32 = 0x4;
pub const COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT: u32 = 0x1;

pub const ApplicationInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_APPLICATION_INFO,
    p_next: ?*const anyopaque = null,
    application_name: ?[*:0]const u8 = null,
    application_version: u32 = 0,
    engine_name: ?[*:0]const u8 = null,
    engine_version: u32 = 0,
    api_version: u32 = API_VERSION_1_0,
};

pub const InstanceCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    application_info: ?*const ApplicationInfo = null,
    enabled_layer_count: u32 = 0,
    enabled_layer_names: ?[*]const [*:0]const u8 = null,
    enabled_extension_count: u32 = 0,
    enabled_extension_names: ?[*]const [*:0]const u8 = null,
};

pub const Extent3D = extern struct {
    width: u32,
    height: u32,
    depth: u32,
};

pub const QueueFamilyProperties = extern struct {
    queue_flags: u32,
    queue_count: u32,
    timestamp_valid_bits: u32,
    min_image_transfer_granularity: Extent3D,
};

pub const DeviceQueueCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    queue_family_index: u32,
    queue_count: u32 = 1,
    queue_priorities: [*]const f32,
};

pub const DeviceCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    queue_create_info_count: u32 = 1,
    queue_create_infos: *const DeviceQueueCreateInfo,
    enabled_layer_count: u32 = 0,
    enabled_layer_names: ?[*]const [*:0]const u8 = null,
    enabled_extension_count: u32 = 0,
    enabled_extension_names: ?[*]const [*:0]const u8 = null,
    enabled_features: ?*const anyopaque = null,
};

/// The prefix is ABI-defined. `tail` deliberately exceeds the implementation
/// structure so the loader cannot overwrite a hand-sized placeholder.
pub const PhysicalDeviceProperties = extern struct {
    api_version: u32,
    driver_version: u32,
    vendor_id: u32,
    device_id: u32,
    device_type: u32,
    device_name: [256]u8,
    pipeline_cache_uuid: [16]u8,
    tail: [1024]u8,
};

pub const MemoryType = extern struct {
    property_flags: u32,
    heap_index: u32,
};

pub const MemoryHeap = extern struct {
    size: u64,
    flags: u32,
};

pub const PhysicalDeviceMemoryProperties = extern struct {
    memory_type_count: u32,
    memory_types: [32]MemoryType,
    memory_heap_count: u32,
    memory_heaps: [16]MemoryHeap,
};

pub const BufferCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_BUFFER_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    size: u64,
    usage: u32,
    sharing_mode: u32 = 0,
    queue_family_index_count: u32 = 0,
    queue_family_indices: ?[*]const u32 = null,
};

pub const MemoryRequirements = extern struct {
    size: u64,
    alignment: u64,
    memory_type_bits: u32,
};

pub const MemoryAllocateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    p_next: ?*const anyopaque = null,
    allocation_size: u64,
    memory_type_index: u32,
};

pub const CommandPoolCreateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    queue_family_index: u32,
};

pub const CommandBufferAllocateInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    p_next: ?*const anyopaque = null,
    command_pool: NonDispatchable,
    level: u32 = 0,
    command_buffer_count: u32 = 1,
};

pub const CommandBufferBeginInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    p_next: ?*const anyopaque = null,
    flags: u32 = COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    inheritance_info: ?*const anyopaque = null,
};

pub const SubmitInfo = extern struct {
    s_type: u32 = STRUCTURE_TYPE_SUBMIT_INFO,
    p_next: ?*const anyopaque = null,
    wait_semaphore_count: u32 = 0,
    wait_semaphores: ?[*]const NonDispatchable = null,
    wait_dst_stage_mask: ?[*]const u32 = null,
    command_buffer_count: u32 = 1,
    command_buffers: [*]const CommandBuffer,
    signal_semaphore_count: u32 = 0,
    signal_semaphores: ?[*]const NonDispatchable = null,
};

pub extern fn vkCreateInstance(*const InstanceCreateInfo, ?*const anyopaque, *Instance) Result;
pub extern fn vkDestroyInstance(Instance, ?*const anyopaque) void;
pub extern fn vkEnumeratePhysicalDevices(Instance, *u32, ?[*]PhysicalDevice) Result;
pub extern fn vkGetPhysicalDeviceProperties(PhysicalDevice, *PhysicalDeviceProperties) void;
pub extern fn vkGetPhysicalDeviceQueueFamilyProperties(PhysicalDevice, *u32, ?[*]QueueFamilyProperties) void;
pub extern fn vkGetPhysicalDeviceMemoryProperties(PhysicalDevice, *PhysicalDeviceMemoryProperties) void;
pub extern fn vkCreateDevice(PhysicalDevice, *const DeviceCreateInfo, ?*const anyopaque, *Device) Result;
pub extern fn vkDestroyDevice(Device, ?*const anyopaque) void;
pub extern fn vkGetDeviceQueue(Device, u32, u32, *Queue) void;
pub extern fn vkDeviceWaitIdle(Device) Result;

pub extern fn vkCreateBuffer(Device, *const BufferCreateInfo, ?*const anyopaque, *NonDispatchable) Result;
pub extern fn vkDestroyBuffer(Device, NonDispatchable, ?*const anyopaque) void;
pub extern fn vkGetBufferMemoryRequirements(Device, NonDispatchable, *MemoryRequirements) void;
pub extern fn vkAllocateMemory(Device, *const MemoryAllocateInfo, ?*const anyopaque, *NonDispatchable) Result;
pub extern fn vkFreeMemory(Device, NonDispatchable, ?*const anyopaque) void;
pub extern fn vkBindBufferMemory(Device, NonDispatchable, NonDispatchable, u64) Result;
pub extern fn vkMapMemory(Device, NonDispatchable, u64, u64, u32, *?*anyopaque) Result;
pub extern fn vkUnmapMemory(Device, NonDispatchable) void;

pub extern fn vkCreateCommandPool(Device, *const CommandPoolCreateInfo, ?*const anyopaque, *NonDispatchable) Result;
pub extern fn vkDestroyCommandPool(Device, NonDispatchable, ?*const anyopaque) void;
pub extern fn vkAllocateCommandBuffers(Device, *const CommandBufferAllocateInfo, *CommandBuffer) Result;
pub extern fn vkBeginCommandBuffer(CommandBuffer, *const CommandBufferBeginInfo) Result;
pub extern fn vkCmdFillBuffer(CommandBuffer, NonDispatchable, u64, u64, u32) void;
pub extern fn vkEndCommandBuffer(CommandBuffer) Result;
pub extern fn vkQueueSubmit(Queue, u32, [*]const SubmitInfo, NonDispatchable) Result;
pub extern fn vkQueueWaitIdle(Queue) Result;
