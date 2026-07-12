//! Content-addressed, append-only replay chains for official Arena runs.

const std = @import("std");

pub const algorithm_id = "sha256-chain-v1";
const domain = "yard-arena/replay/sha256-chain-v1";
pub const zero_hash_hex = "0000000000000000000000000000000000000000000000000000000000000000";

pub const Event = struct {
    sequence: u64,
    kind: []const u8,
    payload: []const u8,
    previous_sha256: []const u8,
    payload_sha256: []const u8,
    event_sha256: []const u8,
};

pub const OwnedEvent = struct {
    sequence: u64,
    kind: []const u8,
    payload: []const u8,
    previous_sha256: [64]u8,
    payload_sha256: [64]u8,
    event_sha256: [64]u8,

    pub fn view(self: *const OwnedEvent) Event {
        return .{
            .sequence = self.sequence,
            .kind = self.kind,
            .payload = self.payload,
            .previous_sha256 = &self.previous_sha256,
            .payload_sha256 = &self.payload_sha256,
            .event_sha256 = &self.event_sha256,
        };
    }
};

pub const Chain = struct {
    count: u64 = 0,
    head: [32]u8 = [_]u8{0} ** 32,

    pub fn append(self: *Chain, kind: []const u8, payload: []const u8) OwnedEvent {
        var payload_digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(payload, &payload_digest, .{});

        const previous_hex = std.fmt.bytesToHex(self.head, .lower);
        const payload_hex = std.fmt.bytesToHex(payload_digest, .lower);
        const event_digest = eventHash(self.count, &self.head, kind, payload);
        const event_hex = std.fmt.bytesToHex(event_digest, .lower);
        self.head = event_digest;
        defer self.count += 1;

        return .{
            .sequence = self.count,
            .kind = kind,
            .payload = payload,
            .previous_sha256 = previous_hex,
            .payload_sha256 = payload_hex,
            .event_sha256 = event_hex,
        };
    }

    pub fn headHex(self: Chain) [64]u8 {
        return std.fmt.bytesToHex(self.head, .lower);
    }
};

pub fn verify(events: []const Event) bool {
    var previous: [32]u8 = [_]u8{0} ** 32;
    for (events, 0..) |event, index| {
        if (event.sequence != index) return false;
        var recorded_previous: [32]u8 = undefined;
        var recorded_payload: [32]u8 = undefined;
        var recorded_event: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&recorded_previous, event.previous_sha256) catch return false;
        _ = std.fmt.hexToBytes(&recorded_payload, event.payload_sha256) catch return false;
        _ = std.fmt.hexToBytes(&recorded_event, event.event_sha256) catch return false;
        if (!std.mem.eql(u8, &previous, &recorded_previous)) return false;

        var payload_digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(event.payload, &payload_digest, .{});
        if (!std.mem.eql(u8, &payload_digest, &recorded_payload)) return false;

        const expected = eventHash(event.sequence, &previous, event.kind, event.payload);
        if (!std.mem.eql(u8, &expected, &recorded_event)) return false;
        previous = expected;
    }
    return true;
}

fn eventHash(sequence: u64, previous: *const [32]u8, kind: []const u8, payload: []const u8) [32]u8 {
    var sequence_bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &sequence_bytes, sequence, .big);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(domain);
    hasher.update("\x00");
    hasher.update(&sequence_bytes);
    hasher.update(previous);
    hasher.update(kind);
    hasher.update("\x00");
    hasher.update(payload);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

test "replay chain verifies and detects payload or order tampering" {
    var chain: Chain = .{};
    const a = chain.append("run_started", "seed=17781001");
    const b = chain.append("vessel_completed", "scenario=0;vessel=0;days=148.25");
    const owned = [_]OwnedEvent{ a, b };
    var events: [owned.len]Event = undefined;
    for (&events, &owned) |*event, *item| event.* = item.view();
    try std.testing.expect(verify(&events));

    var tampered = events;
    tampered[1].payload = "scenario=0;vessel=0;days=1";
    try std.testing.expect(!verify(&tampered));

    var reordered = [_]Event{ events[1], events[0] };
    try std.testing.expect(!verify(&reordered));
}

test "empty replay is a valid zero-length chain" {
    try std.testing.expect(verify(&.{}));
    const empty: Chain = .{};
    try std.testing.expectEqualStrings(zero_hash_hex, &empty.headHex());
}
