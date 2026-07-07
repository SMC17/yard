# Status

yard-ais-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `armor.decodeSymbol` | `unit-tested` | '0'->0, 'W'->39, '`'->40, 'w'->63 |
| `armor.encodeSymbol` | `unit-tested` | round-trip over [0, 63] |
| `armor.decodePayload` | `unit-tested` | '0' -> six zeros; 'w' -> six ones |
| `armor.readUnsigned` | `unit-tested` | '1' -> decimal 1 |
| `armor.readSigned` | `unit-tested` | 0xFE/8 -> -2; 0x7F/8 -> +127 |
| `nmea.xorChecksum` | `unit-tested` | GPGLL canonical example 0x27 |
| `nmea.verifySentence` | `unit-tested` | accepts GPGLL and AIVDM examples; rejects bad sentinel, missing '*', mismatch |
| `message1.decode` | `unit-tested` | standard AIVDM payload reproduces msg_id=1, repeat=0, mmsi=366,053,209 (verified against Python reference decoder) |
| `message1.{longitudeDeg, latitudeDeg, sogKnots}` | `unit-tested` | unit conversions |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `23/23 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: decoder gates on supported message types
  (1, 2, 3 share the bit layout) and rejects all others rather than
  silently producing fields under an unrelated layout. The kernel
  also validates payload length before extraction.
- Type-II missed risk guard: typed-error rejection for invalid
  armoring symbols, missing checksum, bad sentinel, mismatched
  checksum.
- Type-III category guard: bit-level decoder only; not a real-time
  AIS receiver / VHF demodulator; not a track-prediction / collision-
  avoidance engine; not an anti-spoofing layer.

## What is not covered (v0.0.0)

- Encoder for non-trivial AIS messages.
- Multi-fragment message CRC verification.
- AIS message types 4..27 type-specific decoding.
- Physical-layer demodulation.
- Real-time stream tokenisation.
- Anti-tampering / replay detection.

## Composition

- Output `longitude_10000min`, `latitude_10000min` feed
  `yard-routing-zig` great-circle distance and bearing.
- Compose with traffic-density / pattern-of-life analyses for
  ship-routing studies.
