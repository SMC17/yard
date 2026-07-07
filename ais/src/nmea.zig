const std = @import("std");

pub const Error = error{
    InvalidSentence,
    MissingChecksum,
    BadChecksum,
};

/// Compute the NMEA 0183 XOR checksum over the sentence body. Input
/// is the raw character span excluding any leading '$' or '!' sentinel
/// and the trailing `*HH` checksum block.
pub fn xorChecksum(body: []const u8) u8 {
    var c: u8 = 0;
    for (body) |b| c ^= b;
    return c;
}

/// Verify the checksum on a complete NMEA 0183 sentence. The sentence
/// must begin with '$' or '!' and contain a trailing `*HH` block.
pub fn verifySentence(sentence: []const u8) Error!void {
    if (sentence.len < 4) return Error.InvalidSentence;
    if (sentence[0] != '$' and sentence[0] != '!') return Error.InvalidSentence;
    // Locate '*'.
    var star: ?usize = null;
    var i: usize = 1;
    while (i < sentence.len) : (i += 1) {
        if (sentence[i] == '*') {
            star = i;
            break;
        }
    }
    const idx = star orelse return Error.MissingChecksum;
    if (idx + 2 >= sentence.len) return Error.MissingChecksum;
    const body = sentence[1..idx];
    const cs_str = sentence[idx + 1 ..][0..2];
    const computed = xorChecksum(body);
    const supplied = parseHexByte(cs_str) catch return Error.BadChecksum;
    if (computed != supplied) return Error.BadChecksum;
}

fn parseHexByte(s: []const u8) Error!u8 {
    if (s.len < 2) return Error.MissingChecksum;
    const hi = hexNibble(s[0]) orelse return Error.BadChecksum;
    const lo = hexNibble(s[1]) orelse return Error.BadChecksum;
    return (hi << 4) | lo;
}

fn hexNibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'A'...'F' => c - 'A' + 10,
        'a'...'f' => c - 'a' + 10,
        else => null,
    };
}

test "xorChecksum on empty body is zero" {
    try std.testing.expectEqual(@as(u8, 0), xorChecksum(""));
}

test "xorChecksum on known string" {
    // Per NMEA spec example: "GPGLL,5057.970,N,00146.110,E,142451,A"
    // checksum is 0x27. The body is the part between '$' and '*'.
    const body = "GPGLL,5057.970,N,00146.110,E,142451,A";
    const cs = xorChecksum(body);
    try std.testing.expectEqual(@as(u8, 0x27), cs);
}

test "verifySentence: valid GPGLL example" {
    const s = "$GPGLL,5057.970,N,00146.110,E,142451,A*27";
    try verifySentence(s);
}

test "verifySentence: AIVDM AIS example" {
    // Standard example from IEC 61162-1 Annex E.
    const s = "!AIVDM,1,1,,B,15M67FC000G?ufbE`FepT@3n00Sa,0*5C";
    try verifySentence(s);
}

test "verifySentence: rejects missing '*'" {
    const s = "$GPGLL,5057.970,N,00146.110,E,142451,A";
    try std.testing.expectError(Error.MissingChecksum, verifySentence(s));
}

test "verifySentence: rejects bad sentinel" {
    const s = "GPGLL,5057.970,N,00146.110,E,142451,A*27";
    try std.testing.expectError(Error.InvalidSentence, verifySentence(s));
}

test "verifySentence: rejects mismatched checksum" {
    const s = "$GPGLL,5057.970,N,00146.110,E,142451,A*28";
    try std.testing.expectError(Error.BadChecksum, verifySentence(s));
}
