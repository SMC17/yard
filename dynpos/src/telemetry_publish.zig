//! Local integration publisher for ArmadaClaw/NATS telemetry verification.

const std = @import("std");
const dynpos = @import("yard_dynpos");

pub fn main(init: std.process.Init) !u8 {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();
    _ = args.next();
    const count = if (args.next()) |text| try std.fmt.parseInt(u64, text, 10) else 1000;
    if (count == 0) return error.InvalidCount;

    var publisher = try dynpos.nats_telemetry.NatsPublisher.init();
    defer publisher.close();

    const session_timestamp = std.Io.Clock.real.now(init.io).nanoseconds;
    const safe_timestamp: u64 = if (session_timestamp < 0) 0 else @intCast(session_timestamp);
    var session_buffer: [64]u8 = undefined;
    const session_id = try std.fmt.bufPrint(&session_buffer, "zig-smoke-{d}", .{safe_timestamp});

    var sequence: u64 = 0;
    while (sequence < count) : (sequence += 1) {
        const now = std.Io.Clock.real.now(init.io).nanoseconds;
        const sent_at: u64 = if (now < 0) 0 else @intCast(now);
        try publisher.publishStateFrame(init.gpa, .{
            .vessel_id = "zig-vessel-01",
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

    var stdout_buffer: [256]u8 = undefined;
    var stdout_file_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;
    try stdout.print("published={d} subject={s} schema={s}\n", .{
        count,
        dynpos.nats_telemetry.state_subject,
        dynpos.telemetry_protocol.schema_id,
    });
    try stdout.flush();
    return 0;
}
