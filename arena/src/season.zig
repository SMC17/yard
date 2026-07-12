//! Hidden-season commitments and detached Ed25519 signature envelopes.

const std = @import("std");

pub const signature_algorithm = "ed25519-domain-sha256-v2";
pub const signature_domain = "yard-arena/hidden-season-signature/v2";

pub const SignatureEnvelope = struct {
    algorithm: []const u8 = signature_algorithm,
    key_id: []const u8,
    payload_sha256: [64]u8,
    public_key_hex: [64]u8,
    signature_hex: [128]u8,
};

pub fn payloadCommitment(payload: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(payload, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn sign(payload: []const u8, key_id: []const u8, seed: [std.crypto.sign.Ed25519.KeyPair.seed_length]u8) !SignatureEnvelope {
    const key_pair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(seed);
    const commitment = payloadCommitment(payload);
    const digest = signingDigest(key_id, commitment);
    const signature = try key_pair.sign(&digest, null);
    return .{
        .key_id = key_id,
        .payload_sha256 = commitment,
        .public_key_hex = std.fmt.bytesToHex(key_pair.public_key.toBytes(), .lower),
        .signature_hex = std.fmt.bytesToHex(signature.toBytes(), .lower),
    };
}

pub fn verify(payload: []const u8, envelope: SignatureEnvelope) bool {
    if (!std.mem.eql(u8, envelope.algorithm, signature_algorithm)) return false;
    if (!std.mem.eql(u8, &payloadCommitment(payload), &envelope.payload_sha256)) return false;

    var public_key_bytes: [std.crypto.sign.Ed25519.PublicKey.encoded_length]u8 = undefined;
    var signature_bytes: [std.crypto.sign.Ed25519.Signature.encoded_length]u8 = undefined;
    _ = std.fmt.hexToBytes(&public_key_bytes, &envelope.public_key_hex) catch return false;
    _ = std.fmt.hexToBytes(&signature_bytes, &envelope.signature_hex) catch return false;
    const public_key = std.crypto.sign.Ed25519.PublicKey.fromBytes(public_key_bytes) catch return false;
    const signature = std.crypto.sign.Ed25519.Signature.fromBytes(signature_bytes);
    const digest = signingDigest(envelope.key_id, envelope.payload_sha256);
    signature.verifyStrict(&digest, public_key) catch return false;
    return true;
}

fn signingDigest(key_id: []const u8, payload_sha256: [64]u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(signature_domain);
    hasher.update(&.{0});
    hasher.update(signature_algorithm);
    hasher.update(&.{0});
    hasher.update(key_id);
    hasher.update(&.{0});
    hasher.update(&payload_sha256);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

pub fn verifyReveal(hidden_manifest: []const u8, committed_sha256: []const u8) bool {
    if (committed_sha256.len != 64) return false;
    return std.mem.eql(u8, &payloadCommitment(hidden_manifest), committed_sha256);
}

test "season signatures bind exact bytes and hidden reveal commitments" {
    var seed: [std.crypto.sign.Ed25519.KeyPair.seed_length]u8 = undefined;
    for (&seed, 0..) |*byte, i| byte.* = @intCast(i);
    const manifest = "{\"schema\":\"yard.arena.hidden-season.v0\",\"seeds\":[11,12,13]}\n";
    const envelope = try sign(manifest, "yard-test-key", seed);
    try std.testing.expect(verify(manifest, envelope));
    try std.testing.expect(!verify("{}\n", envelope));
    var renamed = envelope;
    renamed.key_id = "rewritten-key-id";
    try std.testing.expect(!verify(manifest, renamed));
    try std.testing.expect(verifyReveal(manifest, &envelope.payload_sha256));
    try std.testing.expect(!verifyReveal("tampered", &envelope.payload_sha256));
}
