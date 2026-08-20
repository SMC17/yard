const std = @import("std");

// MARKED 2026-07-20: not part of this project's build (build.zig only
// compiles the src/root.zig tree -- armor/nmea/message1; this file is not
// imported by root.zig or anything under it). Found with two functions
// both named `publishPrint`, which cannot compile as written -- fixed
// below by renaming the first to make the naming collision unambiguous.
// That renamed function does not compute anything: it fabricates
// "exact_lightship_t"/beam/draft naval-architecture figures from the
// *string length* of a debug-print message and publishes them to
// `naval.yacht.calculated` as though they were real measurements. Do not
// wire this module into any build, and do not treat that topic's output
// as real data if this ever gets copied elsewhere. See yard-ais-zig
// STATUS.md / project history for context on how this file got here.

/// Lightweight Zero-Dependency NATS Telemetry Publisher
/// This module allows any sovereign-physics `yard-*` module to broadcast its internal mathematical
/// computations directly onto the Stax Mesh NATS broker over native Linux sockets.
pub const NatsPublisher = struct {
    sock: i32,
    
    pub fn init() !NatsPublisher {
        const sock_fd = std.os.linux.socket(std.os.linux.AF.INET, std.os.linux.SOCK.STREAM, 0);
        const sock = @as(i32, @intCast(sock_fd));
        if (sock < 0) return error.SocketFailed;

        var addr = std.os.linux.sockaddr.in{
            .family = std.os.linux.AF.INET,
            .port = std.mem.nativeToBig(u16, 4222),
            .addr = std.mem.nativeToBig(u32, 0x7f000001), // 127.0.0.1
            .zero = [_]u8{0} ** 8,
        };

        const res = std.os.linux.connect(sock, @ptrCast(&addr), @sizeOf(std.os.linux.sockaddr.in));
        if (@as(i32, @intCast(res)) < 0) return error.ConnectionRefused;

        return NatsPublisher{ .sock = sock };
    }

    pub fn publish(self: *const NatsPublisher, topic: []const u8, payload: []const u8) !void {
        var buf: [1024]u8 = undefined;
        // Construct the NATS PUB protocol string: PUB <topic> <size>\r\n<payload>\r\n
        const msg = try std.fmt.bufPrint(&buf, "PUB {s} {d}\r\n{s}\r\n", .{ topic, payload.len, payload });
        
        const wres = std.os.linux.write(self.sock, msg.ptr, msg.len);
        if (@as(i32, @intCast(wres)) < 0) return error.WriteFailed;
    }
    
    pub fn close(self: *const NatsPublisher) void {
        _ = std.os.linux.close(self.sock);
    }
};

/// FABRICATED OUTPUT, NOT A REAL COMPUTATION: every numeric field below
/// (lightship tonnage, length, beam, draft) is derived purely from how
/// many characters long the formatted debug message happens to be, then
/// dressed up in naval-architecture units and labeled "exact_*" as if it
/// were a real calculation. This function is preserved as-found (renamed
/// only, to fix a duplicate-definition compile error) rather than deleted,
/// but it must not be called from real code, and nothing consuming the
/// `naval.yacht.calculated` NATS topic should trust its payload.
pub fn publishFabricatedYachtStatsDoNotUse(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
    if (NatsPublisher.init()) |publ| {
        var buf: [1024]u8 = undefined;
        if (std.fmt.bufPrint(&buf, fmt, args)) |msg| {
            var json_buf: [2048]u8 = undefined;
            // Generate deterministic but variable stats based on string length
            const length = msg.len * 2;
            const beam = msg.len / 2;
            const draft = msg.len / 4;
            const mass = msg.len * 100;

            // Extract a pseudo-name from the format string or use a default
            const json = std.fmt.bufPrint(&json_buf,
                "{{\"name\":\"MODEL-YARD-{d}\",\"exact_lightship_t\":{d},\"exact_parameters\":{{\"length_m\":{d},\"beam_m\":{d},\"draft_m\":{d}}}}}",
                .{ msg.len, mass, length, beam, draft }
            ) catch return;

            publ.publish("naval.yacht.calculated", json) catch {};
        } else |_| {}
        publ.close();
    } else |_| {}
}

/// The real, non-fabricating publisher: prints locally and forwards the
/// exact formatted message verbatim, with no invented fields.
pub fn publishPrint(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
    if (NatsPublisher.init()) |publ| {
        var buf: [1024]u8 = undefined;
        if (std.fmt.bufPrint(&buf, fmt, args)) |msg| {
            publ.publish("homelab.venue.classified", msg) catch {};
        } else |_| {}
        publ.close();
    } else |_| {}
}
