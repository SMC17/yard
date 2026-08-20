const std = @import("std");
const nats = @import("nats_telemetry.zig");

// Compile-check only. Does not call init/publish (would dial 127.0.0.1:4222)
// and does not invoke publishFabricatedYachtStatsDoNotUse.
test "nats_telemetry compiles without connecting" {
    std.testing.refAllDecls(nats);
    std.testing.refAllDecls(nats.NatsPublisher);
}
