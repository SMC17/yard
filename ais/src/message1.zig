const std = @import("std");
const armor = @import("armor.zig");

pub const Error = error{
    PayloadTooShort,
    UnsupportedMessageType,
    InvalidValue,
    InvalidSymbol,
};

/// ITU-R M.1371 Message type 1 (Position Report Class A) decoded
/// fields. Bit layout per ITU-R M.1371-5 Annex 8.
pub const PositionReportClassA = struct {
    /// Message identifier. 1 for class-A position report.
    msg_id: u6,
    /// Repeat indicator [0, 3].
    repeat: u2,
    /// Maritime Mobile Service Identity.
    mmsi: u32,
    /// Navigation status code [0, 15] per ITU-R M.1371-5 Table 45.
    nav_status: u4,
    /// Rate of turn in 8-bit twos complement units (-128 indicates not
    /// available, +127 right at >5 deg / 30 s, -127 left at the same).
    rate_of_turn: i8,
    /// Speed over ground in 0.1 knot units (1023 = not available).
    sog_decikt: u10,
    /// Position accuracy: 1 = DGPS, 0 = unaugmented.
    position_accuracy: u1,
    /// Longitude in 1/10000 minute units (181 degrees * 600 000 = not avail).
    longitude_10000min: i32,
    /// Latitude  in 1/10000 minute units.
    latitude_10000min: i32,
    /// Course over ground in 0.1 degree units (3600 = not available).
    cog_decideg: u12,
    /// True heading in degrees (511 = not available).
    true_heading_deg: u9,
    /// UTC second of the position report (60 = not available).
    timestamp_s: u6,
    /// Manoeuvre indicator [0, 3].
    manoeuvre: u2,
    /// RAIM flag.
    raim: u1,
    /// Radio status (DSC + comm state).
    radio_status: u19,
};

/// Decode an AIS Message type 1 from the bit array. Caller is
/// responsible for armouring decoding via `armor.decodePayload`.
pub fn decode(bits: []const u1) Error!PositionReportClassA {
    if (bits.len < 168) return Error.PayloadTooShort;
    const msg_id = try armor.readUnsigned(bits, 0, 6);
    if (msg_id != 1 and msg_id != 2 and msg_id != 3) return Error.UnsupportedMessageType;
    const r = PositionReportClassA{
        .msg_id = @intCast(msg_id),
        .repeat = @intCast(try armor.readUnsigned(bits, 6, 2)),
        .mmsi = @intCast(try armor.readUnsigned(bits, 8, 30)),
        .nav_status = @intCast(try armor.readUnsigned(bits, 38, 4)),
        .rate_of_turn = @intCast(try armor.readSigned(bits, 42, 8)),
        .sog_decikt = @intCast(try armor.readUnsigned(bits, 50, 10)),
        .position_accuracy = @intCast(try armor.readUnsigned(bits, 60, 1)),
        .longitude_10000min = @intCast(try armor.readSigned(bits, 61, 28)),
        .latitude_10000min = @intCast(try armor.readSigned(bits, 89, 27)),
        .cog_decideg = @intCast(try armor.readUnsigned(bits, 116, 12)),
        .true_heading_deg = @intCast(try armor.readUnsigned(bits, 128, 9)),
        .timestamp_s = @intCast(try armor.readUnsigned(bits, 137, 6)),
        .manoeuvre = @intCast(try armor.readUnsigned(bits, 143, 2)),
        .raim = @intCast(try armor.readUnsigned(bits, 148, 1)),
        .radio_status = @intCast(try armor.readUnsigned(bits, 149, 19)),
    };
    return r;
}

/// Convenience wrapper: decode the message1 fields directly from the
/// ASCII-armored payload string (caller-supplied bit buffer must hold
/// at least payload.len * 6 bits).
pub fn decodeFromPayload(payload: []const u8, bit_buf: []u1) Error!PositionReportClassA {
    if (bit_buf.len < payload.len * 6) return Error.InvalidValue;
    armor.decodePayload(payload, bit_buf[0 .. payload.len * 6]) catch return Error.InvalidValue;
    return try decode(bit_buf[0 .. payload.len * 6]);
}

/// Longitude in degrees from the integer-1/10000-minute field.
pub fn longitudeDeg(lon_10000min: i32) f64 {
    return @as(f64, @floatFromInt(lon_10000min)) / 600_000.0;
}

/// Latitude in degrees from the integer-1/10000-minute field.
pub fn latitudeDeg(lat_10000min: i32) f64 {
    return @as(f64, @floatFromInt(lat_10000min)) / 600_000.0;
}

/// Speed over ground in knots from the 0.1 kt field.
pub fn sogKnots(sog_decikt: u10) f64 {
    return @as(f64, @floatFromInt(sog_decikt)) / 10.0;
}

test "decode standard IEC 61162-1 Annex E example payload" {
    // !AIVDM,1,1,,B,15M67FC000G?ufbE`FepT@3n00Sa,0*5C
    // Verified by Python reference decoder: msg_id=1, repeat=0,
    // mmsi=366053209.
    var bits: [28 * 6]u1 = undefined;
    const msg = try decodeFromPayload("15M67FC000G?ufbE`FepT@3n00Sa", &bits);
    try std.testing.expectEqual(@as(u6, 1), msg.msg_id);
    try std.testing.expectEqual(@as(u2, 0), msg.repeat);
    try std.testing.expectEqual(@as(u32, 366_053_209), msg.mmsi);
}

test "decode rejects payload shorter than 168 bits" {
    const bits = [_]u1{0} ** 100;
    try std.testing.expectError(Error.PayloadTooShort, decode(&bits));
}

test "longitudeDeg conversion" {
    // 1 degree = 600 000 in the 1/10000-minute integer field.
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), longitudeDeg(600_000), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -1.0), longitudeDeg(-600_000), 1e-12);
}

test "latitudeDeg conversion" {
    try std.testing.expectApproxEqAbs(@as(f64, 45.0), latitudeDeg(27_000_000), 1e-12);
}

test "sogKnots conversion" {
    try std.testing.expectApproxEqAbs(@as(f64, 12.3), sogKnots(123), 1e-12);
}

test "decode unsupported message type returns error" {
    // Build a 168-bit pattern with msg_id = 5 (static voyage data).
    var bits: [168]u1 = .{0} ** 168;
    bits[0] = 0;
    bits[1] = 0;
    bits[2] = 0;
    bits[3] = 1;
    bits[4] = 0;
    bits[5] = 1; // 000101 = 5
    try std.testing.expectError(Error.UnsupportedMessageType, decode(&bits));
}
