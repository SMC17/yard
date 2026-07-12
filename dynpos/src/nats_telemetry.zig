//! Minimal NATS publisher for the versioned dynamic-positioning telemetry wire.

const std = @import("std");
const protocol = @import("telemetry_protocol.zig");

pub const state_subject = "yard.telemetry.v1.state";
pub const command_subject = "yard.telemetry.v1.thrusters";
pub const connect_preamble = "CONNECT {\"verbose\":false,\"pedantic\":true,\"echo\":false,\"lang\":\"zig\",\"version\":\"0.1.0\"}\r\n";

pub const Error = error{
    SocketFailed,
    ConnectionRefused,
    WriteFailed,
    ReadFailed,
    InvalidHandshake,
    InvalidSubject,
    PayloadTooLarge,
    OutOfMemory,
    InvalidEnvelope,
    InvalidIdentifier,
    InvalidNumber,
    InvalidFrame,
    ParseFailed,
};

pub const NatsPublisher = struct {
    socket: i32,

    pub fn init() Error!NatsPublisher {
        return .{ .socket = try connectSocket() };
    }

    pub fn publish(self: *const NatsPublisher, subject: []const u8, payload: []const u8) Error!void {
        try validateSubject(subject);
        if (payload.len > protocol.max_payload_bytes) return Error.PayloadTooLarge;

        var header_buffer: [256]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buffer, "PUB {s} {d}\r\n", .{ subject, payload.len }) catch
            return Error.InvalidSubject;
        try writeAll(self.socket, header);
        try writeAll(self.socket, payload);
        try writeAll(self.socket, "\r\n");
    }

    pub fn publishStateFrame(
        self: *const NatsPublisher,
        allocator: std.mem.Allocator,
        frame: protocol.StateFrame,
    ) Error!void {
        const payload = protocol.encodeStateFrame(allocator, frame) catch |err| return switch (err) {
            error.OutOfMemory => Error.OutOfMemory,
            error.PayloadTooLarge => Error.PayloadTooLarge,
            error.InvalidEnvelope => Error.InvalidEnvelope,
            error.InvalidIdentifier => Error.InvalidIdentifier,
            error.InvalidNumber => Error.InvalidNumber,
            else => Error.InvalidEnvelope,
        };
        defer allocator.free(payload);
        try self.publish(state_subject, payload);
    }

    pub fn close(self: *const NatsPublisher) void {
        _ = std.os.linux.close(self.socket);
    }

    /// Flush all prior publications through the broker before closing.
    pub fn flush(self: *const NatsPublisher) Error!void {
        try writeAll(self.socket, "PING\r\n");
        try awaitPong(self.socket);
    }
};

pub const NatsCommandSubscriber = struct {
    socket: i32,

    pub fn init() Error!NatsCommandSubscriber {
        const socket = try connectSocket();
        errdefer _ = std.os.linux.close(socket);
        var subscribe_buffer: [256]u8 = undefined;
        const subscribe = std.fmt.bufPrint(&subscribe_buffer, "SUB {s} 1\r\nPING\r\n", .{command_subject}) catch
            return Error.InvalidSubject;
        try writeAll(socket, subscribe);
        try awaitPong(socket);
        return .{ .socket = socket };
    }

    pub fn readCommand(
        self: *const NatsCommandSubscriber,
        allocator: std.mem.Allocator,
    ) Error!std.json.Parsed(protocol.ThrusterCommand) {
        var line_buffer: [4096]u8 = undefined;
        while (true) {
            const raw_line = try readLine(self.socket, &line_buffer);
            const line = std.mem.trim(u8, raw_line, "\r\n");
            if (std.mem.eql(u8, line, "PING")) {
                try writeAll(self.socket, "PONG\r\n");
                continue;
            }
            if (!std.mem.startsWith(u8, line, "MSG ")) continue;

            const payload_length = try parseMessageLength(line);
            if (payload_length > protocol.max_payload_bytes) return Error.PayloadTooLarge;
            const payload = allocator.alloc(u8, payload_length) catch return Error.OutOfMemory;
            defer allocator.free(payload);
            try readExact(self.socket, payload);
            var terminator: [2]u8 = undefined;
            try readExact(self.socket, &terminator);
            if (!std.mem.eql(u8, &terminator, "\r\n")) return Error.InvalidFrame;
            return protocol.parseCommand(allocator, payload) catch |err| return switch (err) {
                error.OutOfMemory => Error.OutOfMemory,
                error.PayloadTooLarge => Error.PayloadTooLarge,
                error.InvalidEnvelope => Error.InvalidEnvelope,
                error.InvalidIdentifier => Error.InvalidIdentifier,
                error.InvalidNumber => Error.InvalidNumber,
                else => Error.ParseFailed,
            };
        }
    }

    pub fn close(self: *const NatsCommandSubscriber) void {
        _ = std.os.linux.close(self.socket);
    }
};

pub fn formatPublishHeader(buffer: []u8, subject: []const u8, payload_len: usize) Error![]const u8 {
    try validateSubject(subject);
    if (payload_len > protocol.max_payload_bytes) return Error.PayloadTooLarge;
    return std.fmt.bufPrint(buffer, "PUB {s} {d}\r\n", .{ subject, payload_len }) catch Error.InvalidSubject;
}

fn validateSubject(subject: []const u8) Error!void {
    if (subject.len == 0 or subject.len > 192) return Error.InvalidSubject;
    for (subject) |byte| {
        if (byte <= ' ' or byte == '*' or byte == '>') return Error.InvalidSubject;
    }
}

fn connectSocket() Error!i32 {
    const linux = std.os.linux;
    const socket_result = linux.socket(linux.AF.INET, linux.SOCK.STREAM, linux.IPPROTO.TCP);
    if (isSyscallError(socket_result)) return Error.SocketFailed;
    const socket: i32 = @intCast(socket_result);
    errdefer _ = linux.close(socket);

    var address = linux.sockaddr.in{
        .family = linux.AF.INET,
        .port = std.mem.nativeToBig(u16, 4222),
        .addr = @bitCast([4]u8{ 127, 0, 0, 1 }),
        .zero = [_]u8{0} ** 8,
    };

    const connect_result = linux.connect(socket, @ptrCast(&address), @sizeOf(linux.sockaddr.in));
    if (connect_result != 0) return Error.ConnectionRefused;

    var greeting_buffer: [4096]u8 = undefined;
    const greeting = try readLine(socket, &greeting_buffer);
    if (!std.mem.startsWith(u8, greeting, "INFO ")) return Error.InvalidHandshake;
    try writeAll(socket, connect_preamble);
    return socket;
}

fn awaitPong(socket: i32) Error!void {
    var line_buffer: [4096]u8 = undefined;
    while (true) {
        const line = try readLine(socket, &line_buffer);
        if (std.mem.startsWith(u8, line, "PONG")) return;
        if (std.mem.startsWith(u8, line, "PING")) try writeAll(socket, "PONG\r\n");
    }
}

fn parseMessageLength(line: []const u8) Error!usize {
    var fields = std.mem.splitScalar(u8, line, ' ');
    const command = fields.next() orelse return Error.InvalidFrame;
    if (!std.mem.eql(u8, command, "MSG")) return Error.InvalidFrame;
    const subject = fields.next() orelse return Error.InvalidFrame;
    if (!std.mem.eql(u8, subject, command_subject)) return Error.InvalidFrame;
    _ = fields.next() orelse return Error.InvalidFrame;

    var last = fields.next() orelse return Error.InvalidFrame;
    while (fields.next()) |field| last = field;
    return std.fmt.parseInt(usize, last, 10) catch Error.InvalidFrame;
}

fn writeAll(socket: i32, bytes: []const u8) Error!void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const result = std.os.linux.write(@intCast(socket), bytes.ptr + offset, bytes.len - offset);
        if (isSyscallError(result) or result == 0) return Error.WriteFailed;
        offset += result;
    }
}

fn readLine(socket: i32, buffer: []u8) Error![]const u8 {
    var length: usize = 0;
    while (length < buffer.len) {
        const result = std.os.linux.read(@intCast(socket), buffer.ptr + length, 1);
        if (isSyscallError(result) or result == 0) return Error.ReadFailed;
        length += result;
        if (buffer[length - 1] == '\n') return buffer[0..length];
    }
    return Error.InvalidHandshake;
}

fn readExact(socket: i32, buffer: []u8) Error!void {
    var offset: usize = 0;
    while (offset < buffer.len) {
        const result = std.os.linux.read(@intCast(socket), buffer.ptr + offset, buffer.len - offset);
        if (isSyscallError(result) or result == 0) return Error.ReadFailed;
        offset += result;
    }
}

fn isSyscallError(result: usize) bool {
    return result > std.math.maxInt(usize) - 4096;
}

test "NATS publish header binds the versioned subject and exact payload length" {
    var buffer: [256]u8 = undefined;
    const header = try formatPublishHeader(&buffer, state_subject, 321);
    try std.testing.expectEqualStrings("PUB yard.telemetry.v1.state 321\r\n", header);
}

test "NATS publish header rejects wildcard and oversized payloads" {
    var buffer: [256]u8 = undefined;
    try std.testing.expectError(Error.InvalidSubject, formatPublishHeader(&buffer, "yard.*", 1));
    try std.testing.expectError(
        Error.PayloadTooLarge,
        formatPublishHeader(&buffer, state_subject, protocol.max_payload_bytes + 1),
    );
}

test "NATS command MSG header accepts direct and reply-to forms" {
    try std.testing.expectEqual(@as(usize, 321), try parseMessageLength("MSG yard.telemetry.v1.thrusters 1 321"));
    try std.testing.expectEqual(@as(usize, 44), try parseMessageLength("MSG yard.telemetry.v1.thrusters 1 reply.inbox 44"));
    try std.testing.expectError(Error.InvalidFrame, parseMessageLength("MSG other.subject 1 10"));
}
