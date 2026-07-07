# yard-ais-zig

Proof level: `unit-tested`

yard-ais-zig is a Zig 0.16 AIS NMEA 0183 + ITU-R M.1371 kernel.
Three modules: `armor` for the 6-bit ASCII armoring used by AIVDM /
AIVDO sentences; `nmea` for sentence-level XOR-checksum compute and
verify; `message1` for ITU-R M.1371 message-type-1 (Position Report
Class A) bit-field decode.

## What it does

### armor
- `armor.decodeSymbol(c)` maps the printable ASCII '0'..'W' and
  '`'..'w' ranges to the 6-bit value space [0, 63].
- `armor.encodeSymbol(v)` inverse mapping for `v in [0, 63]`.
- `armor.decodePayload(payload, out_bits)` MSB-first bit unpacking.
- `armor.readUnsigned(bits, offset, width)`, `readSigned` two's
  complement extraction from a bit slice.

### nmea
- `nmea.xorChecksum(body)` 8-bit XOR over the sentence body.
- `nmea.verifySentence(sentence)` end-to-end checksum verification
  of a `$...*HH` or `!...*HH` sentence.

### message1
- `message1.PositionReportClassA` typed struct with msg_id, repeat,
  mmsi, nav_status, rate_of_turn, sog_decikt, position_accuracy,
  longitude_10000min, latitude_10000min, cog_decideg, true_heading_deg,
  timestamp_s, manoeuvre, raim, radio_status.
- `message1.decode(bits)` decodes from a 168-bit MSB-first slice.
- `message1.decodeFromPayload(payload, bit_buf)` wraps armor decode.
- `message1.longitudeDeg`, `latitudeDeg`, `sogKnots` unit conversions.

## What it is not (v0.0.0)

- No encoder for non-trivial AIS messages (encode primitive exists,
  full message-type-1 encoder deferred).
- No CRC verification of multi-fragment messages (single-fragment
  type-1 only).
- No message types 2..27 (decoder for 2 and 3 share the bit layout
  and pass the same gate, but the kernel does not validate type-
  specific fields).
- No physical-layer demodulation (assumes already-armoured AIVDM
  text payloads).
- No real-time stream tokenisation (caller splits to one sentence
  per `verifySentence` call).
- No anti-tampering / signal-replay detection.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 23/23 tests passed`.

## Public API

```zig
const yard = @import("yard_ais");

const s = "!AIVDM,1,1,,B,15M67FC000G?ufbE`FepT@3n00Sa,0*5C";
try yard.nmea.verifySentence(s);

var bit_buf: [28 * 6]u1 = undefined;
const msg = try yard.message1.decodeFromPayload(
    "15M67FC000G?ufbE`FepT@3n00Sa", &bit_buf);
const lon_deg = yard.message1.longitudeDeg(msg.longitude_10000min);
const lat_deg = yard.message1.latitudeDeg(msg.latitude_10000min);
const sog_kt = yard.message1.sogKnots(msg.sog_decikt);
```

## Validation

- `decodeSymbol('0') = 0`, `decodeSymbol('W') = 39`,
  `decodeSymbol('`')` (backtick) `= 40`, `decodeSymbol('w') = 63`.
- `encodeSymbol(v)` round-trips for the full [0, 63] range.
- Invalid armoring symbols rejected.
- 6-bit payload `'0'` yields six zero bits; `'w'` yields six one bits.
- `readUnsigned` of `'1'` = decimal 1; `readSigned` of 0xFE / 8 bits
  = -2; 0x7F / 8 bits = +127.
- `xorChecksum("")` = 0; `xorChecksum("GPGLL,5057.970,N,...,A")` =
  0x27.
- `verifySentence` accepts the GPGLL example with checksum 0x27, the
  AIVDM example with checksum 0x5C, rejects bad sentinel, missing
  `*HH`, and mismatched checksum.
- AIS message-type-1 decoder reproduces (msg_id=1, repeat=0,
  mmsi=366,053,209) from the standard `15M67FC000G?ufbE`FepT@3n00Sa`
  payload (verified against an independent Python reference
  decoder).
- Longitude / latitude / SOG unit conversions match `1 deg =
  600 000` and `0.1 kt = 1` field unit.
- Decoder rejects payload shorter than 168 bits and unsupported
  message types (kernel accepts 1, 2, 3 only).

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- ITU-R Recommendation M.1371-5. *Technical characteristics for an
  automatic identification system using time-division multiple
  access in the VHF maritime mobile band*.
- IEC 61162-1. *Maritime navigation and radiocommunication equipment
  and systems - Digital interfaces*. Section 9.4 (NMEA 0183 sentence
  structure).
- IMO Resolution A.917(22). *Guidelines for the onboard operational
  use of shipborne AIS*.

## License

Apache-2.0.
