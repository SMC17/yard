//! Closed-loop Zig -> NATS -> ArmadaClaw -> NATS -> Zig protocol proof.

const std = @import("std");
const dynpos = @import("yard_dynpos");

pub fn main(init: std.process.Init) !u8 {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();
    _ = args.next();
    const count = if (args.next()) |text| try std.fmt.parseInt(u64, text, 10) else 100;
    if (count == 0) return error.InvalidCount;

    var subscriber = try dynpos.nats_telemetry.NatsCommandSubscriber.init();
    defer subscriber.close();
    var publisher = try dynpos.nats_telemetry.NatsPublisher.init();
    defer publisher.close();

    const session_timestamp = std.Io.Clock.real.now(init.io).nanoseconds;
    const safe_timestamp: u64 = if (session_timestamp < 0) 0 else @intCast(session_timestamp);
    var session_buffer: [64]u8 = undefined;
    const session_id = try std.fmt.bufPrint(&session_buffer, "zig-loop-{d}", .{safe_timestamp});

    var sequence: u64 = 0;
    while (sequence < count) : (sequence += 1) {
        const now = std.Io.Clock.real.now(init.io).nanoseconds;
        const sent_at: u64 = if (now < 0) 0 else @intCast(now);
        try publisher.publishStateFrame(init.gpa, .{
            .vessel_id = "zig-loop-vessel-01",
            .session_id = session_id,
            .sequence = sequence,
            .sent_at_unix_ns = sent_at,
            .simulation_time_ns = sequence * 10_000_000,
            .state = .{
                .x_m = 10.0,
                .y_m = -2.0,
                .heading_rad = 0.1,
                .surge_mps = 3.0,
                .sway_mps = 0.2,
                .yaw_rate_radps = 0.001,
            },
        });
    }
    try publisher.flush();

    var received: u64 = 0;
    while (received < count) : (received += 1) {
        const parsed = try subscriber.readCommand(init.gpa);
        defer parsed.deinit();
        if (!std.mem.eql(u8, parsed.value.vessel_id, "zig-loop-vessel-01") or
            !std.mem.eql(u8, parsed.value.session_id, session_id) or
            parsed.value.telemetry_sequence != received)
            return error.CommandSequenceMismatch;
    }

    var stdout_buffer: [256]u8 = undefined;
    var stdout_file_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;
    try stdout.print("published={d} received={d} schema={s}\n", .{
        count,
        received,
        dynpos.telemetry_protocol.schema_id,
    });
    try stdout.flush();
    return 0;
}
