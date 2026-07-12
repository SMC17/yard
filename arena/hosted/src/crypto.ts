import type { SignatureEnvelope } from "./contracts";

const encoder = new TextEncoder();

export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0 || !/^[a-f0-9]*$/.test(hex)) throw new Error("invalid lowercase hexadecimal input");
  const bytes = new Uint8Array(hex.length / 2);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

export function base64ToBytes(input: string): Uint8Array {
  const binary = atob(input);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export function bytesToBase64(input: Uint8Array): string {
  let binary = "";
  for (const byte of input) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export async function sha256Bytes(input: BufferSource): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", input));
}

export async function sha256Hex(input: string | Uint8Array): Promise<string> {
  const bytes = typeof input === "string" ? encoder.encode(input) : input;
  return bytesToHex(await sha256Bytes(bytes));
}

export function canonicalJson(value: unknown): string {
  if (value === null || typeof value === "boolean" || typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("canonical JSON rejects non-finite numbers");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    const keys = Object.keys(record).sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalJson(record[key])}`).join(",")}}`;
  }
  throw new Error("unsupported canonical JSON value");
}

export async function secureTokenEqual(provided: string, expected: string): Promise<boolean> {
  const [providedDigest, expectedDigest] = await Promise.all([
    sha256Bytes(encoder.encode(provided)),
    sha256Bytes(encoder.encode(expected))
  ]);
  return crypto.subtle.timingSafeEqual(providedDigest, expectedDigest);
}

export async function verifyDetachedSignature(payload: Uint8Array, envelope: SignatureEnvelope): Promise<boolean> {
  if ((await sha256Hex(payload)) !== envelope.payload_sha256) return false;
  const publicKey = await crypto.subtle.importKey(
    "raw",
    hexToBytes(envelope.public_key_hex),
    { name: "Ed25519" },
    false,
    ["verify"]
  );
  return crypto.subtle.verify(
    { name: "Ed25519" },
    publicKey,
    hexToBytes(envelope.signature_hex),
    payload
  );
}

export interface ResultSignerConfig {
  keyId: string;
  privateKeyPkcs8Base64: string;
  publicKeyHex: string;
}

export async function signResultPayload(payload: unknown, config: ResultSignerConfig): Promise<Record<string, unknown>> {
  const canonical = canonicalJson(payload);
  const bytes = encoder.encode(canonical);
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    base64ToBytes(config.privateKeyPkcs8Base64),
    { name: "Ed25519" },
    false,
    ["sign"]
  );
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, privateKey, bytes));
  const publicKey = await crypto.subtle.importKey(
    "raw",
    hexToBytes(config.publicKeyHex),
    { name: "Ed25519" },
    false,
    ["verify"]
  );
  if (!(await crypto.subtle.verify({ name: "Ed25519" }, publicKey, signature, bytes))) {
    throw new Error("result signing public key does not match the configured private key");
  }
  return {
    schema_version: "yard.hosted.signed-result.v1",
    payload,
    payload_sha256: await sha256Hex(bytes),
    signature: {
      algorithm: "ed25519-detached-sha256-v1",
      key_id: config.keyId,
      public_key_hex: config.publicKeyHex,
      signature_hex: bytesToHex(signature)
    }
  };
}

const replayDomain = encoder.encode("yard-arena/replay/sha256-chain-v1");
const zeroHash = new Uint8Array(32);

export interface ReplaySummary {
  eventCount: number;
  headSha256: string;
}

export async function verifyReplayNdjson(input: string, maxEvents = 1_000_000): Promise<ReplaySummary> {
  const lines = input.endsWith("\n") ? input.slice(0, -1).split("\n") : input.split("\n");
  if (lines.length === 1 && lines[0] === "") return { eventCount: 0, headSha256: bytesToHex(zeroHash) };
  if (lines.length > maxEvents) throw new Error("replay event limit exceeded");

  let previous: Uint8Array<ArrayBufferLike> = zeroHash;
  for (let sequence = 0; sequence < lines.length; sequence += 1) {
    const parsed = JSON.parse(lines[sequence] ?? "") as Record<string, unknown>;
    if (parsed.sequence !== sequence || typeof parsed.kind !== "string" || typeof parsed.payload !== "string") {
      throw new Error(`invalid replay event at sequence ${sequence}`);
    }
    if (parsed.previous_sha256 !== bytesToHex(previous)) throw new Error(`broken replay predecessor at sequence ${sequence}`);
    const payloadBytes = encoder.encode(parsed.payload);
    const payloadHash = await sha256Bytes(payloadBytes);
    if (parsed.payload_sha256 !== bytesToHex(payloadHash)) throw new Error(`invalid replay payload hash at sequence ${sequence}`);

    const sequenceBytes = new Uint8Array(8);
    new DataView(sequenceBytes.buffer).setBigUint64(0, BigInt(sequence), false);
    const kindBytes = encoder.encode(parsed.kind);
    const material = new Uint8Array(replayDomain.length + 1 + 8 + 32 + kindBytes.length + 1 + payloadBytes.length);
    let offset = 0;
    material.set(replayDomain, offset); offset += replayDomain.length;
    material[offset] = 0; offset += 1;
    material.set(sequenceBytes, offset); offset += 8;
    material.set(previous, offset); offset += 32;
    material.set(kindBytes, offset); offset += kindBytes.length;
    material[offset] = 0; offset += 1;
    material.set(payloadBytes, offset);
    previous = await sha256Bytes(material);
    if (parsed.event_sha256 !== bytesToHex(previous)) throw new Error(`invalid replay event hash at sequence ${sequence}`);
  }
  return { eventCount: lines.length, headSha256: bytesToHex(previous) };
}
