# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `armor.decodeSymbol`, `encodeSymbol`, `decodePayload`,
  `readUnsigned`, `readSigned`.
- `nmea.xorChecksum` and `verifySentence`.
- `message1.PositionReportClassA` typed struct.
- `message1.decode` and `decodeFromPayload`.
- `message1.longitudeDeg`, `latitudeDeg`, `sogKnots`.
- 23-test unit suite including round-trip armor codec, GPGLL
  checksum, AIVDM verify, standard AIS payload decode against an
  independent Python reference (mmsi=366,053,209), and typed-error
  rejection across all three modules.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
