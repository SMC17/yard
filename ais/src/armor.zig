const std = @import("std");

pub const Error = error{
    InvalidSymbol,
    InvalidValue,
};

/// Decode a single 6-bit ASCII-armored AIS payload character to its
/// 6-bit value [0, 63] per IEC 61162-1 Section 9.4.4.
///
///   ASCII 48..87  -> value = ascii - 48     (covers '0'..'W')
///   ASCII 96..119 -> value = ascii - 56     (covers '`'..'w')
pub fn decodeSymbol(c: u8) Error!u6 {
    if (c >= 48 and c <= 87) {
        return @intCast(c - 48);
    }
    if (c >= 96 and c <= 119) {
        return @intCast(c - 56);
    }
    return Error.InvalidSymbol;
}

/// Encode a 6-bit value to its ASCII-armored representation. Inverse
/// of `decodeSymbol`.
pub fn encodeSymbol(v: u6) Error!u8 {
    if (v <= 39) return @intCast(@as(u8, v) + 48);
    if (v <= 63) return @intCast(@as(u8, v) + 56);
    return Error.InvalidValue;
}

/// Decode an ASCII-armored payload string into a bitstream of length
/// `payload_chars * 6` bits, returned MSB-first in `out`. The output
/// buffer must hold at least `payload_chars * 6` bits.
pub fn decodePayload(payload: []const u8, out_bits: []u1) Error!void {
    if (out_bits.len < payload.len * 6) return Error.InvalidValue;
    var bit_idx: usize = 0;
    for (payload) |c| {
        const v = try decodeSymbol(c);
        var b: u3 = 6;
        while (b > 0) {
            b -= 1;
            out_bits[bit_idx] = @intCast((@as(u8, v) >> b) & 0x1);
            bit_idx += 1;
        }
    }
}

/// Read an unsigned integer from a bit slice MSB-first.
pub fn readUnsigned(bits: []const u1, offset: usize, width: usize) Error!u64 {
    if (offset + width > bits.len) return Error.InvalidValue;
    if (width > 64) return Error.InvalidValue;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < width) : (i += 1) {
        v = (v << 1) | @as(u64, bits[offset + i]);
    }
    return v;
}

/// Read a signed integer from a bit slice using two's complement
/// MSB-first.
pub fn readSigned(bits: []const u1, offset: usize, width: usize) Error!i64 {
    const u = try readUnsigned(bits, offset, width);
    if (width == 0) return 0;
    const sign_bit: u64 = @as(u64, 1) << @intCast(width - 1);
    if (u & sign_bit != 0) {
        const mask: u64 = if (width >= 64) ~@as(u64, 0) else (@as(u64, 1) << @intCast(width)) - 1;
        const negated = (~u +% 1) & mask;
        return -@as(i64, @intCast(negated));
    }
    return @as(i64, @intCast(u));
}

test "decode '0' yields 0; 'W' yields 39" {
    try std.testing.expectEqual(@as(u6, 0), try decodeSymbol('0'));
    try std.testing.expectEqual(@as(u6, 39), try decodeSymbol('W'));
}

test "decode backtick `'`' yields 40; 'w' yields 63" {
    try std.testing.expectEqual(@as(u6, 40), try decodeSymbol('`'));
    try std.testing.expectEqual(@as(u6, 63), try decodeSymbol('w'));
}

test "encode round-trips for the entire 0..63 range" {
    var v: u6 = 0;
    while (v < 63) : (v += 1) {
        const c = try encodeSymbol(v);
        const back = try decodeSymbol(c);
        try std.testing.expectEqual(v, back);
    }
    // v = 63
    try std.testing.expectEqual(@as(u6, 63), try decodeSymbol(try encodeSymbol(63)));
}

test "decode invalid symbol rejected" {
    try std.testing.expectError(Error.InvalidSymbol, decodeSymbol('X'));
    try std.testing.expectError(Error.InvalidSymbol, decodeSymbol('\\'));
    try std.testing.expectError(Error.InvalidSymbol, decodeSymbol('x'));
}

test "decode payload '0' yields six zero bits" {
    var bits: [6]u1 = undefined;
    try decodePayload("0", &bits);
    for (bits) |b| try std.testing.expectEqual(@as(u1, 0), b);
}

test "decode payload 'w' yields six one bits" {
    var bits: [6]u1 = undefined;
    try decodePayload("w", &bits);
    for (bits) |b| try std.testing.expectEqual(@as(u1, 1), b);
}

test "readUnsigned: MSB-first 6 bits of '1' = decimal 1" {
    var bits: [6]u1 = undefined;
    try decodePayload("1", &bits);
    const v = try readUnsigned(&bits, 0, 6);
    try std.testing.expectEqual(@as(u64, 1), v);
}

test "readSigned: 0xFE in 8 bits is -2" {
    const bits = [_]u1{ 1, 1, 1, 1, 1, 1, 1, 0 };
    const s = try readSigned(&bits, 0, 8);
    try std.testing.expectEqual(@as(i64, -2), s);
}

test "readSigned: 0x7F in 8 bits is +127" {
    const bits = [_]u1{ 0, 1, 1, 1, 1, 1, 1, 1 };
    const s = try readSigned(&bits, 0, 8);
    try std.testing.expectEqual(@as(i64, 127), s);
}
