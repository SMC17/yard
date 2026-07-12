import { describe, expect, it } from "vitest";
import {
  bytesToBase64,
  bytesToHex,
  canonicalJson,
  sha256Hex,
  signResultPayload,
  verifyDetachedSignature,
  verifyReplayNdjson
} from "../src/crypto";
import type { SignatureEnvelope } from "../src/contracts";

const replay = [
  "{\"sequence\":0,\"kind\":\"run_started\",\"payload\":\"mission=mercury-1778-outbound;submission=example-three-merchantmen;seed=17781001;scenarios=256;environment=d022038f13bbe8e53f3c1c45cc0e7849b07718d5413c676e286b2cb17c748999;dataset=cliwoc-mercury-route-1750-1805-v0\",\"previous_sha256\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"payload_sha256\":\"1fc35d0199cab773fcd45fade35ae20707644de22c11875a41fa63d10c004fb8\",\"event_sha256\":\"b9749e9e39f85c9363ade34d23d458f082628e5a5227b0c4a52dc17e86829e34\"}",
  "{\"sequence\":1,\"kind\":\"vessel_completed\",\"payload\":\"scenario=0;vessel=0;design=merchantman-38m;lost=false;days=233.619414411;cargo_t=180.000000;crew_lost=0;weather=b3f4b73baf39a28fe3991f5f99f6028fb494c37569ad09fe2e9a7f48570c46ea\",\"previous_sha256\":\"b9749e9e39f85c9363ade34d23d458f082628e5a5227b0c4a52dc17e86829e34\",\"payload_sha256\":\"415bd59bc5c4b09150ebc8d80b8693aab78774efa47ca90bba9d309aae169dab\",\"event_sha256\":\"c7700895789fbd28a3e107ccaa9414d6b732c1e79de3dd63200ca8174be7ba88\"}"
].join("\n") + "\n";

describe("cryptographic bindings", () => {
  it("canonicalizes object keys and rejects replay tampering", async () => {
    expect(canonicalJson({ z: 1, a: [true, null] })).toBe('{"a":[true,null],"z":1}');
    const summary = await verifyReplayNdjson(replay);
    expect(summary).toEqual({
      eventCount: 2,
      headSha256: "c7700895789fbd28a3e107ccaa9414d6b732c1e79de3dd63200ca8174be7ba88"
    });
    await expect(verifyReplayNdjson(replay.replace("days=233", "days=1"))).rejects.toThrow("payload hash");
  });

  it("verifies exact-byte season signatures and signs canonical results", async () => {
    const keys = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]) as CryptoKeyPair;
    const payload = new TextEncoder().encode('{"season":"test"}\n');
    const signature = new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, keys.privateKey, payload));
    const publicKeyBuffer = await crypto.subtle.exportKey("raw", keys.publicKey) as ArrayBuffer;
    const publicKey = new Uint8Array(publicKeyBuffer);
    const envelope: SignatureEnvelope = {
      algorithm: "ed25519-detached-sha256-v1",
      key_id: "test-key",
      payload_sha256: await sha256Hex(payload),
      public_key_hex: bytesToHex(publicKey),
      signature_hex: bytesToHex(signature)
    };
    await expect(verifyDetachedSignature(payload, envelope)).resolves.toBe(true);
    await expect(verifyDetachedSignature(new TextEncoder().encode("{}\n"), envelope)).resolves.toBe(false);

    const pkcs8Buffer = await crypto.subtle.exportKey("pkcs8", keys.privateKey) as ArrayBuffer;
    const pkcs8 = new Uint8Array(pkcs8Buffer);
    const signed = await signResultPayload({ run_id: "run-1", value: 7 }, {
      keyId: "test-key",
      privateKeyPkcs8Base64: bytesToBase64(pkcs8),
      publicKeyHex: bytesToHex(publicKey)
    });
    expect(signed.schema_version).toBe("yard.hosted.signed-result.v1");
    expect((signed.signature as Record<string, string>).signature_hex).toMatch(/^[a-f0-9]{128}$/);

    const otherKeys = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]) as CryptoKeyPair;
    const otherPublic = new Uint8Array(await crypto.subtle.exportKey("raw", otherKeys.publicKey) as ArrayBuffer);
    await expect(signResultPayload({ run_id: "run-1", value: 7 }, {
      keyId: "test-key",
      privateKeyPkcs8Base64: bytesToBase64(pkcs8),
      publicKeyHex: bytesToHex(otherPublic)
    })).rejects.toThrow("does not match");
  });
});
