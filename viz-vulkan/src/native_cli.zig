const std = @import("std");
const viewer = @import("yard_viz_vulkan");

pub fn main(init: std.process.Init) !u8 {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(allocator);
    var iterator = try init.minimal.args.iterateAllocator(allocator);
    defer iterator.deinit();
    while (iterator.next()) |arg| try args.append(allocator, arg);
    if (args.items.len < 2) {
        std.log.err("usage: native-frame <scene.json> [-o frame.ppm] [--width N] [--height N]", .{});
        return 1;
    }

    var output_path: []const u8 = "fleet-frame.ppm";
    var width: u32 = 960;
    var height: u32 = 540;
    var index: usize = 2;
    while (index < args.items.len) : (index += 1) {
        if (std.mem.eql(u8, args.items[index], "-o") and index + 1 < args.items.len) {
            output_path = args.items[index + 1];
            index += 1;
        } else if (std.mem.eql(u8, args.items[index], "--width") and index + 1 < args.items.len) {
            width = std.fmt.parseInt(u32, args.items[index + 1], 10) catch {
                std.log.err("invalid --width", .{});
                return 1;
            };
            index += 1;
        } else if (std.mem.eql(u8, args.items[index], "--height") and index + 1 < args.items.len) {
            height = std.fmt.parseInt(u32, args.items[index + 1], 10) catch {
                std.log.err("invalid --height", .{});
                return 1;
            };
            index += 1;
        } else {
            std.log.err("unknown argument: {s}", .{args.items[index]});
            return 1;
        }
    }

    const json = readFileAll(allocator, init.io, args.items[1]) catch |err| {
        std.log.err("cannot read {s}: {s}", .{ args.items[1], @errorName(err) });
        return 1;
    };
    const parsed = viewer.scene.parseSceneJson(allocator, json) catch |err| {
        std.log.err("invalid scene: {s}", .{@errorName(err)});
        return 1;
    };

    var device = viewer.vulkan_draw.Device.init() catch |err| {
        std.log.err("Vulkan initialization failed: {s}", .{@errorName(err)});
        return 2;
    };
    defer device.deinit();
    const probe = device.probe();
    const ppm = device.drawFleetFramePpm(allocator, parsed, width, height) catch |err| {
        std.log.err("native frame failed: {s}", .{@errorName(err)});
        return 2;
    };

    var output = try std.Io.Dir.cwd().createFile(init.io, output_path, .{});
    defer output.close(init.io);
    var write_buffer: [8192]u8 = undefined;
    var writer = output.writer(init.io, &write_buffer);
    try writer.interface.writeAll(ppm);
    try writer.interface.flush();
    std.log.info(
        "Vulkan device={s} vendor=0x{x} device=0x{x} api={d}.{d}.{d} queue_family={d}",
        .{
            probe.device_name,
            probe.vendor_id,
            probe.device_id,
            probe.api_version >> 22,
            (probe.api_version >> 12) & 0x3ff,
            probe.api_version & 0xfff,
            probe.queue_family_index,
        },
    );
    std.log.info("wrote {s} ({d} bytes, {d} vessels)", .{ output_path, ppm.len, parsed.vessels.len });
    return 0;
}

fn readFileAll(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const stat = try file.stat(io);
    const buffer = try allocator.alloc(u8, stat.size);
    var read_buffer: [8192]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    var offset: usize = 0;
    while (offset < buffer.len) {
        const count = try reader.interface.readSliceShort(buffer[offset..]);
        if (count == 0) break;
        offset += count;
    }
    return buffer[0..offset];
}
