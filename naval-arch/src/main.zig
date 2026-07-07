const std = @import("std");
const net = std.net;
const json = std.json;

// Domain Model: Yacht Intake
const YachtIntake = struct {
    id: []const u8,
    name: []const u8,
    length_m: f64,
    beam_m: f64,
    draft_m: f64,
};

// Domain Model: Computed Physics Profile
const YachtPhysicsProfile = struct {
    id: []const u8,
    lightship_displacement_tons: f64,
    hull_speed_knots: f64,
};

const sockaddr_in = extern struct {
    family: u16,
    port: u16,
    addr: u32,
    zero: [8]u8 = [_]u8{0} ** 8,
};

fn writeAll(fd: i32, data: []const u8) !void {
    var written: usize = 0;
    while (written < data.len) {
        const rc = std.os.linux.write(@intCast(fd), data.ptr + written, data.len - written);
        if (rc > 0xffffffffffff0000) return error.WriteFailed;
        written += rc;
    }
}

fn readLine(fd: i32, buffer: []u8) ![]u8 {
    var len: usize = 0;
    while (len < buffer.len) {
        var byte: [1]u8 = undefined;
        const rc = std.os.linux.read(@intCast(fd), &byte, 1);
        if (rc > 0xffffffffffff0000) return error.ReadFailed;
        if (rc == 0) {
            if (len == 0) return error.Eof;
            break;
        }
        buffer[len] = byte[0];
        len += 1;
        if (byte[0] == '\n') break;
    }
    return buffer[0..len];
}

fn readExact(fd: i32, buffer: []u8) !void {
    var bytes_read: usize = 0;
    while (bytes_read < buffer.len) {
        const rc = std.os.linux.read(@intCast(fd), buffer.ptr + bytes_read, buffer.len - bytes_read);
        if (rc > 0xffffffffffff0000) return error.ReadFailed;
        if (rc == 0) return error.Eof;
        bytes_read += rc;
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const linux = std.os.linux;
    const fd_usize = linux.socket(linux.AF.INET, linux.SOCK.STREAM, linux.IPPROTO.TCP);
    if (fd_usize > 0xffffffffffff0000) return error.SocketFailed;
    const fd: i32 = @intCast(fd_usize);

    var addr: sockaddr_in = undefined;
    addr.family = linux.AF.INET;
    addr.port = std.mem.nativeToBig(u16, 4222);
    // 127.0.0.1 -> 127 | 0 | 0 | (1<<24) for little endian
    addr.addr = @as(u32, @bitCast([4]u8{ 127, 0, 0, 1 }));

    const rc = linux.connect(fd, @as(*const anyopaque, @ptrCast(&addr)), @sizeOf(sockaddr_in));
    if (rc != 0) return error.ConnectFailed;
    
    try writeAll(fd, "CONNECT {\"verbose\":false,\"pedantic\":false,\"lang\":\"zig\"}\r\n");
    try writeAll(fd, "SUB naval.yacht.ingested 1\r\n");
    std.debug.print("[yard-naval-arch] Connected to NATS & subscribed to naval.yacht.ingested\n", .{});

    var buffer: [65536]u8 = undefined;

    while (true) {
        const line = readLine(fd, &buffer) catch |err| {
            if (err == error.Eof) break;
            return err;
        };

        var trimmed = line;
        if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '\n') trimmed = trimmed[0 .. trimmed.len - 1];
        if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '\r') trimmed = trimmed[0 .. trimmed.len - 1];

        if (std.mem.startsWith(u8, trimmed, "PING")) {
            try writeAll(fd, "PONG\r\n");
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, "MSG naval.yacht.ingested 1 ")) {
            var it = std.mem.splitScalar(u8, trimmed, ' ');
            _ = it.next(); _ = it.next(); _ = it.next();
            var size_str = it.next() orelse continue;
            if (it.next()) |actual_size| size_str = actual_size;

            const size = try std.fmt.parseInt(usize, size_str, 10);
            const payload_buf = try allocator.alloc(u8, size);
            defer allocator.free(payload_buf);

            try readExact(fd, payload_buf);
            var crlf: [2]u8 = undefined;
            try readExact(fd, &crlf);

            var parsed = json.parseFromSlice(YachtIntake, allocator, payload_buf, .{ .ignore_unknown_fields = true }) catch continue;
    defer parsed.deinit();

    const intake = parsed.value;

    // --- SOVEREIGN PHYSICS MODEL ---
    // Advanced non-linear regression function to dynamically estimate Block Coefficient (Cb)
    const lb_ratio = intake.length_m / intake.beam_m;
    const alpha = 0.65;
    const beta = -0.04;
    const gamma = 0.0015;
    
    var dynamic_cb = alpha + (beta * lb_ratio) + (gamma * lb_ratio * lb_ratio);
    if (dynamic_cb < 0.35) dynamic_cb = 0.35; // Absolute physical floor
    if (dynamic_cb > 0.60) dynamic_cb = 0.60; // Absolute physical ceiling

    // Density of seawater ~ 1.025 t/m^3
    // Displacement (tons) = L * B * T * Cb * Density
    const displacement = intake.length_m * intake.beam_m * intake.draft_m * dynamic_cb * 1.025;

    // Hull speed heuristic = 1.34 * sqrt(LWL in feet).
    // Rough approximation: LWL ~ 0.9 * LOA.
    const length_ft = intake.length_m * 3.28084;
    const hull_speed = 1.34 * std.math.sqrt(length_ft * 0.9);

    const profile = YachtPhysicsProfile{
        .id = intake.id,
        .lightship_displacement_tons = displacement,
        .hull_speed_knots = hull_speed,
    };

        const out_buf = try std.fmt.allocPrint(allocator, "{{\"id\":\"{s}\",\"lightship_displacement_tons\":{d},\"hull_speed_knots\":{d}}}", .{ profile.id, profile.lightship_displacement_tons, profile.hull_speed_knots });
        defer allocator.free(out_buf);

        const pub_hdr = try std.fmt.allocPrint(allocator, "PUB naval.yacht.calculated {d}\r\n", .{out_buf.len});
        defer allocator.free(pub_hdr);

        try writeAll(fd, pub_hdr);
        try writeAll(fd, out_buf);
        try writeAll(fd, "\r\n");

        std.debug.print("[yard-naval-arch] Calculated Profile for {s}:\n", .{profile.id});
        std.debug.print("  -> Dynamic Block Coefficient (Cb): {d:.4}\n", .{dynamic_cb});
        std.debug.print("  -> Lightship Displacement: {d:.2} tons\n", .{profile.lightship_displacement_tons});
        std.debug.print("  -> Theoretical Hull Speed: {d:.2} knots\n", .{profile.hull_speed_knots});
        }
    }
}
